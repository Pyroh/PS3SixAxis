//
//  PS3SixAxis.m
//  PS3_SixAxis
//
//  Created by Tobias Wetzel on 04.05.10.
//  Copyright 2010 Outcut. All rights reserved.
//

#import "PS3SixAxis.h"

#pragma mark -
#pragma mark conditional macro's

#define DO_BLUETOOTH 1
//#define DO_SET_MASTER (DO_BLUETOOTH && 1)

//#define TRACE 1

#pragma mark -
#pragma mark static globals

enum Button {
    kL2 =               0x01,
	kR2 =               0x02,
	kL1 =               0x04,
	kR1 =               0x08,
	kTriangleButton =   0x10,
	kCircleButton =     0x20,
	kCrossButton =      0x40,
	kSquareButton =     0x80
} ButtonTags;

enum DirectionButton {
	kSelectButton =     0x01,
    kLeftStickButton =  0x02,
    kRightStickButton = 0x04,
	kStartButton =      0x08,
    kUpButton =         0x10,
    kRightButton =      0x20,
	kDownButton =       0x40,
	kLeftButton =       0x80
} DirectionButtonTags;

#pragma mark -
#pragma mark controller structures

struct BUTTONS {
    // Direction Pad
    BOOL up;
    BOOL down;
    BOOL left;
    BOOL right;
    BOOL left_stick;
    BOOL right_stick;
    BOOL select;
    BOOL start;
    // Button Pad
    BOOL left1;
    BOOL right1;
    BOOL left2;
    BOOL right2;
    BOOL triangle;
    BOOL circle;
    BOOL cross;
    BOOL square;
    // PS Button
    BOOL ps;
};

#pragma mark -
#pragma mark static functions

@interface PS3SixAxis (Private)
- (void) parse:(uint8_t*)data l:(CFIndex)length;
- (void) parseUnBuffered:(uint8_t*)data l:(CFIndex)length;
- (void) sendDeviceConnected;
- (void) sendDeviceDisconnected;
- (void) sendDeviceConnectionError:(NSInteger)error;
@end

@implementation PS3SixAxis (Private)

static BOOL isConnected;
static struct BUTTONS buttons;

static int preLeftStickX, preLeftStickY;
static int preRightStickX, preRightStickY;

static unsigned int mx, my, mz;

// ask a IOHIDDevice for a feature report
static IOReturn Get_DeviceFeatureReport(IOHIDDeviceRef inIOHIDDeviceRef, CFIndex inReportID, void* inReportBuffer, CFIndex* ioReportSize) {
	IOReturn result = paramErr;
	if (inIOHIDDeviceRef && ioReportSize && inReportBuffer) {
		result = IOHIDDeviceGetReport(inIOHIDDeviceRef, kIOHIDReportTypeFeature, inReportID, inReportBuffer, ioReportSize);
		if (noErr != result) {
			printf("%s, IOHIDDeviceGetReport error: %ld (0x%08lX ).\n", __PRETTY_FUNCTION__, (long int) result, (long int) result);
		}
	}
	return result;
}

// send a IOHIDDevice a feature report
static IOReturn Set_DeviceFeatureReport(IOHIDDeviceRef inIOHIDDeviceRef, CFIndex inReportID, void* inReportBuffer, CFIndex inReportSize) {
	IOReturn result = paramErr;
	if (inIOHIDDeviceRef && inReportSize && inReportBuffer) {
		result = IOHIDDeviceSetReport(inIOHIDDeviceRef, kIOHIDReportTypeFeature, inReportID, inReportBuffer, inReportSize);
		if (noErr != result) {
			printf("%s, IOHIDDeviceSetReport error: %ld (0x%08lX ).\n", __PRETTY_FUNCTION__, (long int) result, (long int) result);
		}
	}
	return result;
}

// ask a PS3 IOHIDDevice for the bluetooth address of its master
static IOReturn PS3_GetMasterBluetoothAddress(IOHIDDeviceRef inIOHIDDeviceRef, BluetoothDeviceAddress *ioBluetoothDeviceAddress) {
	IOReturn result = noErr;
	CFIndex reportID = 0xF5;
	uint8_t report[8];
	CFIndex reportSize = sizeof(report);
	result = IOHIDDeviceGetReport(inIOHIDDeviceRef, kIOHIDReportTypeFeature, reportID, report, &reportSize);
	if (noErr == result) {
		if (ioBluetoothDeviceAddress) {
			memcpy(ioBluetoothDeviceAddress, &report[2], sizeof(*ioBluetoothDeviceAddress));
		}
	} else{
		printf("%s, IOHIDDeviceGetReport error: %ld (0x%08lX ).\n", __PRETTY_FUNCTION__, (long int) result, (long int) result);
	}
	return result;
}

// this will be called when an input report is received
static void Handle_IOHIDDeviceIOHIDReportCallback(void* inContext, IOReturn inResult, void* inSender, IOHIDReportType inType, uint32_t inReportID, uint8_t* inReport, CFIndex inReportLength) {
	PS3SixAxis *context = (PS3SixAxis*)inContext;
	if(context->useBuffered) {
		[context parse:inReport l:inReportLength];
	} else {
		[context parseUnBuffered:inReport l:inReportLength];
	}
}

static Boolean IOHIDDevice_GetLongProperty_( IOHIDDeviceRef inIOHIDDeviceRef, CFStringRef inKey, long * outValue ) {
	Boolean result = FALSE;
	if (inIOHIDDeviceRef) {
		assert( IOHIDDeviceGetTypeID() == CFGetTypeID( inIOHIDDeviceRef ) );
		CFTypeRef tCFTypeRef = IOHIDDeviceGetProperty( inIOHIDDeviceRef, inKey );
		if ( tCFTypeRef ) {
			// if this is a number
			if ( CFNumberGetTypeID() == CFGetTypeID( tCFTypeRef ) ) {
				// get it's value
				result = CFNumberGetValue( ( CFNumberRef ) tCFTypeRef, kCFNumberSInt32Type, outValue );
			}
		}
	}
	return result;
}

// this will be called when the HID Manager matches a new (hot plugged) HID device
static void Handle_DeviceMatchingCallback(void* inContext, IOReturn inResult, void* inSender, IOHIDDeviceRef inIOHIDDeviceRef) {
	PS3SixAxis *context = (PS3SixAxis*)inContext;
	IOReturn ioReturn = noErr;
	
	// Device VendorID/ProductID:   0x054C/0x0268   (Sony Corporation)
	long vendorID = 0;
	long productID = 0;
	
	IOHIDDevice_GetLongProperty_( inIOHIDDeviceRef, CFSTR( kIOHIDVendorIDKey ), &vendorID );
	IOHIDDevice_GetLongProperty_( inIOHIDDeviceRef, CFSTR( kIOHIDProductIDKey ), &productID );
	
	// Sony PlayStation(R)3 Controller
	if ((0x054C != vendorID) || (0x0268 != productID)) {
		return;
	}
	context->hidDeviceRef = inIOHIDDeviceRef;
	
	CFIndex reportSize = 64;
	uint8_t *report = malloc(reportSize);
	IOHIDDeviceRegisterInputReportCallback(inIOHIDDeviceRef, report, reportSize, Handle_IOHIDDeviceIOHIDReportCallback, inContext);
	
	[context sendDeviceConnected];
}

// this will be called when a HID device is removed (unplugged)
static void Handle_RemovalCallback(void* inContext, IOReturn inResult, void* inSender, IOHIDDeviceRef inIOHIDDeviceRef) {
	PS3SixAxis *context = (PS3SixAxis*)inContext;
	if (context->hidDeviceRef == inIOHIDDeviceRef) {
		context->hidDeviceRef = NULL;
		[context sendDeviceDisconnected];
	}
}

-(void)sendDeviceConnected {
	isConnected = YES;
	if ([delegate respondsToSelector:@selector(onDeviceConnected)]) {
		[delegate onDeviceConnected];
	}
}

-(void)sendDeviceDisconnected {
	isConnected = NO;
	[self disconnect];
	if ([delegate respondsToSelector:@selector(onDeviceDisconnected)]) {
		[delegate onDeviceDisconnected];
	}
}

-(void)sendDeviceConnectionError:(NSInteger)error {
	isConnected = NO;
	if ([delegate respondsToSelector:@selector(onDeviceConnectionError:)]) {
		[delegate onDeviceConnectionError:error];
	}
}

- (void) parseUnBuffered:(uint8_t*)data l:(CFIndex)length {
	
}

-(void)parse:(uint8_t*)data l:(CFIndex)length {
#pragma mark ButtonStates
	//unsigned char ButtonState;
	//memcpy( &ButtonState, &data[3], sizeof( unsigned char ) );
	//printf("data[3] %u\n", data[3]);
    
    struct BUTTONS pre_buttons;
    memcpy( &pre_buttons, &buttons, sizeof(struct BUTTONS ));
    
    buttons.triangle = ((data[3] & kTriangleButton) == kTriangleButton);
    buttons.circle = ((data[3] & kCircleButton) == kCircleButton);
    buttons.cross = ((data[3] & kCrossButton) == kCrossButton);
    buttons.square = ((data[3] & kSquareButton) == kSquareButton);
    buttons.left1 = ((data[3] & kL1) == kL1);
    buttons.left2 = ((data[3] & kL2) == kL2);
    buttons.right1 = ((data[3] & kR1) == kR1);
    buttons.right2 = ((data[3] & kR2) == kR2);
    
#pragma mark DirectionButtons
	//unsigned char DirectionButtonState;
	//memcpy( &DirectionButtonState, &data[2], sizeof( unsigned char ) );
	//printf( "DirectionButtonState: %u\n", data[2] );
    buttons.up = ((data[2] & kUpButton) == kUpButton);
    buttons.right = ((data[2] & kRightButton) == kRightButton);
    buttons.down = ((data[2] & kDownButton) == kDownButton);
    buttons.left = ((data[2] & kLeftButton) == kLeftButton);
    buttons.left_stick = ((data[2] & kLeftStickButton) == kLeftStickButton);
    buttons.right_stick = ((data[2] & kRightStickButton) == kRightStickButton);
    buttons.select = ((data[2] & kSelectButton) == kSelectButton);
    buttons.start = ((data[2] & kStartButton) == kStartButton);
	
#pragma mark select and start button
	if (buttons.select != pre_buttons.select) {
		if ([delegate respondsToSelector:@selector(onSelectButton:)]) {
			[delegate onSelectButton:buttons.select];
		}
	}
	if (buttons.start != pre_buttons.start) {
		if ([delegate respondsToSelector:@selector(onStartButton:)]) {
			[delegate onStartButton:buttons.start];
		}
	}
	
#pragma mark PSButton
	//unsigned char PSButtonState;
	//memcpy( &PSButtonState, &data[4], sizeof( unsigned char ) );
	buttons.ps = (BOOL)data[4];
	if (buttons.ps != pre_buttons.ps) {
		if ([delegate respondsToSelector:@selector(onPSButton:)]) {
			[delegate onPSButton:buttons.ps];
		}
	}
	
#pragma mark LeftStick
	/*
	 unsigned char LeftStickX; // left Joystick X axis 0 - 255, 128 is mid
	 unsigned char LeftStickY; // left Joystick Y axis 0 - 255, 128 is mid
	 memcpy( &LeftStickX, &data[6], sizeof( unsigned char ) );
	 memcpy( &LeftStickY, &data[7], sizeof( unsigned char ) );
	 int leftStickX = (int)LeftStickX;
	 int leftStickY = (int)LeftStickY;
	 */
	int leftStickX = (int)data[6];
	int leftStickY = (int)data[7];
	if ((leftStickX != preLeftStickX) && (leftStickY != preLeftStickY)) {
		/*
		 if ((preLeftStickX < 125 || preLeftStickX > 131) && (preLeftStickY < 125 || preLeftStickY > 131)) {
		 
		 } else {
		 preLeftStickX = 128;
		 preLeftStickY = 128;
		 }
		 */
		//printf( "LeftStick: %d, %d\n", (int)LeftStickX, (int)LeftStickY );
		if ([delegate respondsToSelector:@selector(onLeftStick:pressed:)]) {
			[delegate onLeftStick:NSMakePoint((float)data[6], (float)data[7]) pressed:buttons.left_stick];
		}
		preLeftStickX = leftStickX;
		preLeftStickY = leftStickY;
	}
	
#pragma mark RightStick
	/*
	 unsigned char RightStickX; // right Joystick X axis 0 - 255, 128 is mid
	 unsigned char RightStickY; // right Joystick Y axis 0 - 255, 128 is mid
	 memcpy( &RightStickX, &data[8], sizeof( unsigned char ) );
	 memcpy( &RightStickY, &data[9], sizeof( unsigned char ) );
	 int rsx = (int)RightStickX;
	 int rsy = (int)RightStickY;
	 */
	int rsx = (int)data[8];
	int rsy = (int)data[9];
	if ((rsx != preRightStickX) && (rsy != preRightStickY)) {
		/*
		 if ((preRightStickX < 125 || preRightStickX > 131) && (preRightStickY < 125 || preRightStickY > 131)) {
		 
		 } else {
		 preRightStickX = 128;
		 preRightStickY = 128;
		 }
		 */
		//printf( "RightStick: %d, %d\n", (int)RightStickX, (int)RightStickY );
		if ([delegate respondsToSelector:@selector(onRightStick:pressed:)]) {
			[delegate onRightStick:NSMakePoint((float)data[8], (float)data[9]) pressed:buttons.right_stick];
		}
		preRightStickX = rsx;
		preRightStickY = rsy;
	}
	
#pragma mark Buttons
	// digital Pad Triangle button Trigger
	if(buttons.triangle != pre_buttons.triangle) {
		if (!buttons.triangle && [delegate respondsToSelector:@selector(onTriangleButtonWithPressure:)]) {
			[delegate onTriangleButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onTriangleButton:)]) {
			[delegate onTriangleButton:buttons.triangle];
		}
	}
	// digital Pad Triangle button Pressure 0 - 255
	if(buttons.triangle) {
		if ([delegate respondsToSelector:@selector(onTriangleButtonWithPressure:)]) {
			//unsigned char PressureTriangle;
			//memcpy( &PressureTriangle, &data[22], sizeof( unsigned char ) );
			[delegate onTriangleButtonWithPressure:(NSInteger)data[22]];
		}
	}
	// digital Pad Circle button Trigger
	if(buttons.circle != pre_buttons.circle) {
		if (!buttons.circle && [delegate respondsToSelector:@selector(onCircleButtonWithPressure:)]) {
			[delegate onCircleButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onCircleButton:)]) {
			[delegate onCircleButton:buttons.circle];
		}
	}
	// digital Pad Circle button Pressure 0 - 255
	if(buttons.circle) {
		if ([delegate respondsToSelector:@selector(onCircleButtonWithPressure:)]) {
			//unsigned char PressureCircle;
			//memcpy( &PressureCircle, &data[23], sizeof( unsigned char ) );
			[delegate onCircleButtonWithPressure:(NSInteger)data[23]];
		}
	}
	
	// Cross Button
	// digital Pad Cross button Trigger
	if(buttons.cross != pre_buttons.cross) {
		if (!buttons.cross && [delegate respondsToSelector:@selector(onCrossButtonWithPressure:)]) {
			[delegate onCrossButtonWithPressure:0];
		}		
		if ([delegate respondsToSelector:@selector(onCrossButton:)]) {
			[delegate onCrossButton:buttons.cross];
		}
	}
	// digital Pad Cross button Pressure 0 - 255	
	if(buttons.cross) {
		if ([delegate respondsToSelector:@selector(onCrossButtonWithPressure:)]) {
			//unsigned char PressureCross;
			//memcpy( &PressureCross, &data[24], sizeof( unsigned char ) );
			[delegate onCrossButtonWithPressure:(NSInteger)data[24]];
		}
	}
	
	// Square Button
	// digital Pad Square button Trigger
	if(buttons.square != pre_buttons.square) {
		if (!buttons.square && [delegate respondsToSelector:@selector(onSquareButtonWithPressure:)]) {
			[delegate onSquareButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onSquareButton:)]) {
			[delegate onSquareButton:buttons.square];
		}
	}
	// digital Pad Square button Pressure 0 - 255
	if(buttons.square) {
		if ([delegate respondsToSelector:@selector(onSquareButtonWithPressure:)]) {
			//unsigned char PressureSquare;
			//memcpy( &PressureSquare, &data[25], sizeof( unsigned char ) );
			[delegate onSquareButtonWithPressure:(NSInteger)data[25]];
		}
	}
	
	// L2 Button
	// digital Pad L2 button Trigger
	if(buttons.left2 != pre_buttons.left2) {
		if (!buttons.left2 && [delegate respondsToSelector:@selector(onL2ButtonWithPressure:)]) {
			[delegate onL2ButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onL2Button:)]) {
			[delegate onL2Button:buttons.left2];
		}
	}
	// digital Pad L2 button Pressure 0 - 255
	if(buttons.left2) {
		if ([delegate respondsToSelector:@selector(onL2ButtonWithPressure:)]) {
			//unsigned char PressureL2;
			//memcpy( &PressureL2, &data[18], sizeof( unsigned char ) );
			[delegate onL2ButtonWithPressure:(NSInteger)data[18]];
		}
	}
	
	// R2 Button
	// digital Pad R2 button Trigger
	if(buttons.right2 != pre_buttons.right2) {
		if (!buttons.right2 && [delegate respondsToSelector:@selector(onR2ButtonWithPressure:)]) {
			[delegate onR2ButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onR2Button:)]) {
			[delegate onR2Button:buttons.right2];
		}
	}
	// digital Pad R2 button Pressure 0 - 255
	if(buttons.right2) {
		if ([delegate respondsToSelector:@selector(onR2ButtonWithPressure:)]) {
			//unsigned char PressureR2;
			//memcpy( &PressureR2, &data[19], sizeof( unsigned char ) );
			[delegate onR2ButtonWithPressure:(NSInteger)data[19]];
		}
	}
	
	// L1 Button
	// digital Pad L1 button Trigger
	if(buttons.left1 != pre_buttons.left1) {
		if (!buttons.left1 && [delegate respondsToSelector:@selector(onL1ButtonWithPressure:)]) {
			[delegate onL1ButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onL1Button:)]) {
			[delegate onL1Button:buttons.left1];
		}
	}
	// digital Pad L1 button Pressure 0 - 255
	if(buttons.left1) {
		if ([delegate respondsToSelector:@selector(onL1ButtonWithPressure:)]) {
			//unsigned char PressureL1;
			//memcpy( &PressureL1, &data[20], sizeof( unsigned char ) );
			[delegate onL1ButtonWithPressure:(NSInteger)data[20]];
		}
	}
	
	// R1 Button
	// digital Pad R1 button Trigger
	if(buttons.right1 != pre_buttons.right1) {
		if (!buttons.right1 && [delegate respondsToSelector:@selector(onR1ButtonWithPressure:)]) {
			[delegate onR1ButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onR1Button:)]) {
			[delegate onR1Button:buttons.right1];
		}
	}
	// digital Pad R1 button Pressure 0 - 255
	if(buttons.right1) {
		if ([delegate respondsToSelector:@selector(onR1ButtonWithPressure:)]) {
			//unsigned char PressureR1;
			//memcpy( &PressureR1, &data[21], sizeof( unsigned char ) );
			[delegate onR1ButtonWithPressure:(NSInteger)data[21]];
		}
	}
	
	// North Button
	// Cross North button Trigger
	if(buttons.up != pre_buttons.up) {
		if (!buttons.up && [delegate respondsToSelector:@selector(onNorthButtonWithPressure:)]) {
			[delegate onNorthButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onNorthButton:)]) {
			[delegate onNorthButton:buttons.up];
		}
	}
	// Cross North button Pressure 0 - 255
	if(buttons.up) {
		if ([delegate respondsToSelector:@selector(onNorthButtonWithPressure:)]) {
			//unsigned char PressureNorth;
			//memcpy( &PressureNorth, &data[14], sizeof( unsigned char ) );
			[delegate onNorthButtonWithPressure:(NSInteger)data[14]];
		}
	}
	
	// East Button
	// Cross East button Trigger
	if(buttons.right != pre_buttons.right) {
		if (!buttons.right && [delegate respondsToSelector:@selector(onEastButtonWithPressure:)]) {
			[delegate onEastButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onEastButton:)]) {
			[delegate onEastButton:buttons.right];
		}
	}
	// Cross East button Pressure 0 - 255
	if(buttons.right) {
		if ([delegate respondsToSelector:@selector(onEastButtonWithPressure:)]) {
			//unsigned char PressureEast;
			//memcpy( &PressureEast, &data[15], sizeof( unsigned char ) );
			[delegate onEastButtonWithPressure:(NSInteger)data[15]];
		}
	}
	
	// South Button
	// Cross South button Trigger
	if(buttons.down != pre_buttons.down) {
		if (!buttons.down && [delegate respondsToSelector:@selector(onSouthButtonWithPressure:)]) {
			[delegate onSouthButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onSouthButton:)]) {
			[delegate onSouthButton:buttons.down];
		}
	}
	// Cross South button Pressure 0 - 255
	if(buttons.down) {
		if ([delegate respondsToSelector:@selector(onSouthButtonWithPressure:)]) {
			//unsigned char PressureSouth;
			//memcpy( &PressureSouth, &data[16], sizeof( unsigned char ) );
			[delegate onSouthButtonWithPressure:(NSInteger)data[16]];
		}
	}
	
	// West Button
	// Cross West button Trigger
	if(buttons.left != pre_buttons.left) {
		if (!buttons.left && [delegate respondsToSelector:@selector(onWestButtonWithPressure:)]) {
			[delegate onWestButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onWestButton:)]) {
			[delegate onWestButton:buttons.left];
		}
	}
	// Cross West button Pressure 0 - 255
	if(buttons.left) {
		if ([delegate respondsToSelector:@selector(onWestButtonWithPressure:)]) {
			//unsigned char PressureWest;
			//memcpy( &PressureWest, &data[17], sizeof( unsigned char ) );
			[delegate onWestButtonWithPressure:(NSInteger)data[17]];
		}
	}

	// Accelerometers
    if (length == 48) {
        mx = (data[40] << 8) | data[41];
        my = (data[42] << 8) | data[43];
        mz = (data[44] << 8) | data[45];
    }else { // == 49
        mx = (data[41] << 8) | data[42];
        my = (data[43] << 8) | data[44];
        mz = (data[45] << 8) | data[46];
    }
	

	if ([delegate respondsToSelector:@selector(onAxisX:Y:Z:)]) {
		[delegate onAxisX:mx Y:my Z:mz];
	}
}

@end

@implementation PS3SixAxis

+ (id)sixAixisController {
	return [[self alloc] init];
}

+ (id)sixAixisControllerWithDelegate:(id<PS3SixAxisDelegate>)aDelegate {
	return [[self alloc] initSixAixisControllerWithDelegate:aDelegate];
}

- (id) initSixAixisControllerWithDelegate:(id<PS3SixAxisDelegate>)aDelegate {
	self = [super init];
	if (self) {
		delegate = aDelegate;
		useBuffered = YES;
	}
	return self;
}

- (void) connect:(BOOL)enableBluetooth {
	
	if (hidManagerRef) {
		if(isConnected) {
			if ([delegate respondsToSelector:@selector(onDeviceConnected)]) {
				[delegate onDeviceConnected];
			}
		}
		return;
	}
	
	int error = 0;

	if (enableBluetooth && error != 0) {
		if ([delegate respondsToSelector:@selector(onDeviceConnectionError:)]) {
			[delegate onDeviceConnectionError:error];
		}
		return;
	}
	
	hidManagerRef = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
	if (hidManagerRef) {
		IOHIDManagerSetDeviceMatching(hidManagerRef, NULL);
		//IOHIDManagerSetDeviceMatchingMultiple(hidManagerRef, NULL);
		IOHIDManagerRegisterDeviceMatchingCallback(hidManagerRef, Handle_DeviceMatchingCallback, self);
		IOHIDManagerRegisterDeviceRemovalCallback(hidManagerRef,Handle_RemovalCallback, self);
		IOHIDManagerScheduleWithRunLoop(hidManagerRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		
		IOReturn ioReturn = IOHIDManagerOpen(hidManagerRef, kIOHIDOptionsTypeNone);
		if (noErr != ioReturn) {
			if ([delegate respondsToSelector:@selector(onDeviceConnectionError:)]) {
				[delegate onDeviceConnectionError:(long int)ioReturn];
			}
			//fprintf(stderr, "%s, IOHIDDeviceOpen error: %ld (0x%08lX ).\n", __PRETTY_FUNCTION__, (long int) ioReturn, (long int) ioReturn);
		}
	} else {
		if ([delegate respondsToSelector:@selector(onDeviceConnectionError:)]) {
			[delegate onDeviceConnectionError:3];
		}
	}
	
}

- (void)disconnect {
	if (hidManagerRef) {
		isConnected = NO;
		IOReturn ioReturn = IOHIDManagerClose(hidManagerRef, kIOHIDOptionsTypeNone);
		if (noErr != ioReturn) {
			//fprintf(stderr, "%s, IOHIDManagerClose error: %ld (0x%08lX ).\n", __PRETTY_FUNCTION__, (long int) ioReturn, (long int) ioReturn);
		}
		CFRelease(hidManagerRef);
		hidManagerRef = NULL;
		if ([delegate respondsToSelector:@selector(onDeviceDisconnected)]) {
			[delegate onDeviceDisconnected];
		}
	}
}

- (void) setDelegate:(id<PS3SixAxisDelegate>)aDelegate {
	delegate = aDelegate;
}

- (id<PS3SixAxisDelegate>)delegate {
	return delegate;
}

- (void)setUseBuffered:(BOOL)doUseBuffered {
	useBuffered = doUseBuffered;
}

- (BOOL)useBuffered {
	return useBuffered;
}

@end
