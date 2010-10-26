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
	kButtonsRelease = 0,
	kTriangleButton = 16,
	kCircleButton = 32,
	kTriangleAndCircleButton = 48,
	kCrossButton = 64,
	kTriangleAndCrossButton = 80,
	kCircleAndCrossButton = 96,
	kTriangleAndCircleAndCrossButton = 112,
	kSquareButton = 128,
	kTriangleAndSquareButton = 144,
	kCircleAndSquareButton = 160,
	kTriangleAndSquareAndCircleButton = 176,
	kCrossAndSquareButton = 192,
	kCrossAndSquareAndTriangleButton = 208,
	kCircleAndCrossAndSquareButton = 224,
	kCircleAndCrossAndSquareAndTriangleButton = 240,
	
	
	kL2 = 1,
	kR2 = 2,
	kL2R2 = 3,
	kL1 = 4,
	kL1L2 = 5,
	kL1R2 = 6,
	kL1L2R2 = 7,
	kR1 = 8,
	kR1L2 = 9,
	kR1R2 = 10,
	kR1R2L2 = 11,
	kL1R1 = 12,
	kL1L2R1 = 13,
	kL1R1R2 = 14,
	kL1L2R1R2 = 15
} ButtonTags;

enum DirectionButton {
	kSelectButton = 1,
	kStartButton = 8,
	kSelectAndStartButton = 9,
	kDirectionButtonsRelease = 0,
	kLeftStickButton = 2,
	kRightStickButton = 4,
	kLeftAndRightStickButton = 6,
	kNorthButton = 16,
	kEastButton = 32,
	kNorthEastButton = 48,
	kSouthButton = 64,
	kEastSouthButton = 96,
	kWestButton = 128,
	kWestNorthButton = 144,
	kWestSouthButton = 192
} DirectionButtonTags;

#pragma mark -
#pragma mark static functions

@interface PS3SixAxis (Private)
BOOL isConnected;

BOOL isLeftStickDown, preIsLeftStickDown;
BOOL isRightStickDown, preIsRightStickDown;
BOOL isTriangleButtonDown, preIsTriangleButtonDown;
BOOL isCircleButtonDown, preIsCircleButtonDown;
BOOL isCrossButtonDown, preIsCrossButtonDown;
BOOL isSquareButtonDown, preIsSquareButtonDown;
BOOL isL1ButtonDown, preIsL1ButtonDown;
BOOL isL2ButtonDown, preIsL2ButtonDown;
BOOL isR1ButtonDown, preIsR1ButtonDown;
BOOL isR2ButtonDown, preIsR2ButtonDown;

BOOL isNorthButtonDown, preIsNorthButtonDown;
BOOL isEastButtonDown, preIsEastButtonDown;
BOOL isSouthButtonDown, preIsSouthButtonDown;
BOOL isWestButtonDown, preIsWestButtonDown;

BOOL isSelectButtonDown, preIsSelectButtonDown;
BOOL isStartButtonDown, preIsStartButtonDown;
BOOL isPSButtonDown, preIsPSButtonDown;

int preLeftStickX, preLeftStickY;
int preRightStickX, preRightStickY;

unsigned int mx, my, mz;

- (void) parse:(uint8_t*)data l:(CFIndex)length;
- (void) parseUnBuffered:(uint8_t*)data l:(CFIndex)length;
- (void) sendDeviceConnected;
- (void) sendDeviceDisconnected;
- (void) sendDeviceConnectionError:(NSInteger)error;
@end

@implementation PS3SixAxis (Private)

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
	switch (data[3]) {
		case kButtonsRelease:
			// release all Buttons
			isTriangleButtonDown = NO;
			isCircleButtonDown = NO;
			isCrossButtonDown = NO;
			isSquareButtonDown = NO;
			isL1ButtonDown = NO;
			isL2ButtonDown = NO;
			isR1ButtonDown = NO;
			isR2ButtonDown = NO;
			break;
		case kTriangleButton:
			isTriangleButtonDown = YES;
			isCircleButtonDown = NO;
			isCrossButtonDown = NO;
			isSquareButtonDown = NO;
			break;
		case kTriangleAndCircleButton:
			isTriangleButtonDown = YES;
			isCircleButtonDown = YES;
			isCrossButtonDown = NO;
			isSquareButtonDown = NO;
			break;
		case kTriangleAndCrossButton:
			isTriangleButtonDown = YES;
			isCircleButtonDown = NO;
			isCrossButtonDown = YES;
			isSquareButtonDown = NO;
			break;
		case kTriangleAndSquareButton:
			isTriangleButtonDown = YES;
			isCircleButtonDown = NO;
			isCrossButtonDown = NO;
			isSquareButtonDown = YES;
			break;
		case kCircleButton:
			isTriangleButtonDown = NO;
			isCircleButtonDown = YES;
			isCrossButtonDown = NO;
			isSquareButtonDown = NO;
			break;
		case kCircleAndCrossButton:
			isTriangleButtonDown = NO;
			isCircleButtonDown = YES;
			isCrossButtonDown = YES;
			isSquareButtonDown = NO;
			break;
		case kCircleAndSquareButton:
			isTriangleButtonDown = NO;
			isCircleButtonDown = YES;
			isCrossButtonDown = NO;
			isSquareButtonDown = YES;
			break;
		case kCrossButton:
			isTriangleButtonDown = NO;
			isCircleButtonDown = NO;
			isCrossButtonDown = YES;
			isSquareButtonDown = NO;
			break;
		case kCrossAndSquareButton:
			isTriangleButtonDown = NO;
			isCircleButtonDown = NO;
			isCrossButtonDown = YES;
			isSquareButtonDown = YES;
			break;
		case kSquareButton:
			isTriangleButtonDown = NO;
			isCircleButtonDown = NO;
			isCrossButtonDown = NO;
			isSquareButtonDown = YES;
			break;
		case kTriangleAndCircleAndCrossButton:
			isTriangleButtonDown = YES;
			isCircleButtonDown = YES;
			isCrossButtonDown = YES;
			isSquareButtonDown = NO;
			break;
		case kTriangleAndSquareAndCircleButton:
			isTriangleButtonDown = YES;
			isCircleButtonDown = YES;
			isCrossButtonDown = NO;
			isSquareButtonDown = YES;
			break;
		case kCrossAndSquareAndTriangleButton:
			isTriangleButtonDown = YES;
			isCircleButtonDown = NO;
			isCrossButtonDown = YES;
			isSquareButtonDown = YES;
			break;
		case kCircleAndCrossAndSquareButton:
			isTriangleButtonDown = NO;
			isCircleButtonDown = YES;
			isCrossButtonDown = YES;
			isSquareButtonDown = YES;
			break;
		case kCircleAndCrossAndSquareAndTriangleButton:
			isTriangleButtonDown = YES;
			isCircleButtonDown = YES;
			isCrossButtonDown = YES;
			isSquareButtonDown = YES;
			break;
		case kL1:
			isL1ButtonDown = YES;
			isL2ButtonDown = NO;
			isR1ButtonDown = NO;
			isR2ButtonDown = NO;
			break;
		case kL2:
			isL1ButtonDown = NO;
			isL2ButtonDown = YES;
			isR1ButtonDown = NO;
			isR2ButtonDown = NO;
			break;
		case kR1:
			isL1ButtonDown = NO;
			isL2ButtonDown = NO;
			isR1ButtonDown = YES;
			isR2ButtonDown = NO;
			break;
		case kR2:
			isL1ButtonDown = NO;
			isL2ButtonDown = NO;
			isR1ButtonDown = NO;
			isR2ButtonDown = YES;
			break;
		case kL2R2:
			isL1ButtonDown = NO;
			isL2ButtonDown = YES;
			isR1ButtonDown = NO;
			isR2ButtonDown = YES;
			break;
		case kL1L2:
			isL1ButtonDown = YES;
			isL2ButtonDown = YES;
			isR1ButtonDown = NO;
			isR2ButtonDown = NO;
			break;
		case kL1R2:
			isL1ButtonDown = YES;
			isL2ButtonDown = NO;
			isR1ButtonDown = NO;
			isR2ButtonDown = YES;
			break;
		case kL1L2R2:
			isL1ButtonDown = YES;
			isL2ButtonDown = YES;
			isR1ButtonDown = NO;
			isR2ButtonDown = YES;
			break;
		case kR1L2:
			isL1ButtonDown = NO;
			isL2ButtonDown = YES;
			isR1ButtonDown = YES;
			isR2ButtonDown = NO;
			break;
		case kR1R2:
			isL1ButtonDown = NO;
			isL2ButtonDown = NO;
			isR1ButtonDown = YES;
			isR2ButtonDown = YES;
			break;
		case kR1R2L2:
			isL1ButtonDown = NO;
			isL2ButtonDown = YES;
			isR1ButtonDown = YES;
			isR2ButtonDown = YES;
			break;
		case kL1R1:
			isL1ButtonDown = YES;
			isL2ButtonDown = NO;
			isR1ButtonDown = YES;
			isR2ButtonDown = NO;
			break;
		case kL1L2R1:
			isL1ButtonDown = YES;
			isL2ButtonDown = YES;
			isR1ButtonDown = YES;
			isR2ButtonDown = NO;
			break;
		case kL1R1R2:
			isL1ButtonDown = YES;
			isL2ButtonDown = NO;
			isR1ButtonDown = YES;
			isR2ButtonDown = YES;
			break;
		case kL1L2R1R2:
			isL1ButtonDown = YES;
			isL2ButtonDown = YES;
			isR1ButtonDown = YES;
			isR2ButtonDown = YES;
			break;
		default:
			break;
	}
#pragma mark DirectionButtons
	//unsigned char DirectionButtonState;
	//memcpy( &DirectionButtonState, &data[2], sizeof( unsigned char ) );
	//printf( "DirectionButtonState: %u\n", data[2] );
	switch (data[2]) {
		case kDirectionButtonsRelease:
			// release all Buttons
			isNorthButtonDown = NO;
			isEastButtonDown = NO;
			isSouthButtonDown = NO;
			isWestButtonDown = NO;
			isLeftStickDown = NO;
			isRightStickDown = NO;
			isSelectButtonDown = NO;
			isStartButtonDown = NO;
			break;
		case kNorthButton:
			isNorthButtonDown = YES;
			isEastButtonDown = NO;
			isSouthButtonDown = NO;
			isWestButtonDown = NO;
			break;
		case kEastButton:
			isNorthButtonDown = NO;
			isEastButtonDown = YES;
			isSouthButtonDown = NO;
			isWestButtonDown = NO;
			break;
		case kSouthButton:
			isNorthButtonDown = NO;
			isEastButtonDown = NO;
			isSouthButtonDown = YES;
			isWestButtonDown = NO;
			break;
		case kWestButton:
			isNorthButtonDown = NO;
			isEastButtonDown = NO;
			isSouthButtonDown = NO;
			isWestButtonDown = YES;
			break;
		case kNorthEastButton:
			isNorthButtonDown = YES;
			isEastButtonDown = YES;
			isSouthButtonDown = NO;
			isWestButtonDown = NO;
			break;
		case kEastSouthButton:
			isNorthButtonDown = NO;
			isEastButtonDown = YES;
			isSouthButtonDown = YES;
			isWestButtonDown = NO;
			break;
		case kWestNorthButton:
			isNorthButtonDown = YES;
			isEastButtonDown = NO;
			isSouthButtonDown = NO;
			isWestButtonDown = YES;
			break;
		case kWestSouthButton:
			isNorthButtonDown = NO;
			isEastButtonDown = NO;
			isSouthButtonDown = YES;
			isWestButtonDown = YES;			
			break;
		case kLeftStickButton:
			isLeftStickDown = YES;
			break;
		case kRightStickButton:
			isRightStickDown = YES;
			break;
		case kLeftAndRightStickButton:
			isLeftStickDown = YES;
			isRightStickDown = YES;
			break;
		case kSelectButton:
			isSelectButtonDown = YES;
			break;
		case kStartButton:
			isStartButtonDown = YES;
			break;
		case kSelectAndStartButton:
			isSelectButtonDown = YES;
			isStartButtonDown = YES;
			break;
		default:
			break;
	}
	
#pragma mark select and start button
	if (isSelectButtonDown != preIsSelectButtonDown) {
		if ([delegate respondsToSelector:@selector(onSelectButton:)]) {
			[delegate onSelectButton:isSelectButtonDown];
		}
		preIsSelectButtonDown = isSelectButtonDown;
	}
	if (isStartButtonDown != preIsStartButtonDown) {
		if ([delegate respondsToSelector:@selector(onStartButton:)]) {
			[delegate onStartButton:isStartButtonDown];
		}
		preIsStartButtonDown = isStartButtonDown;
	}
	
#pragma mark PSButton
	//unsigned char PSButtonState;
	//memcpy( &PSButtonState, &data[4], sizeof( unsigned char ) );
	BOOL psb = (BOOL)data[4];
	if (psb != preIsPSButtonDown) {
		if ([delegate respondsToSelector:@selector(onPSButton:)]) {
			[delegate onPSButton:psb];
		}
		preIsPSButtonDown = psb;
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
			[delegate onLeftStick:NSMakePoint((float)data[6], (float)data[7]) pressed:isLeftStickDown];
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
			[delegate onRightStick:NSMakePoint((float)data[8], (float)data[9]) pressed:isRightStickDown];
		}
		preRightStickX = rsx;
		preRightStickY = rsy;
	}
	
#pragma mark Buttons
	// digital Pad Triangle button Trigger
	if(isTriangleButtonDown != preIsTriangleButtonDown) {
		if (!isTriangleButtonDown && [delegate respondsToSelector:@selector(onTriangleButtonWithPressure:)]) {
			[delegate onTriangleButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onTriangleButton:)]) {
			[delegate onTriangleButton:isTriangleButtonDown];
		}
		preIsTriangleButtonDown = isTriangleButtonDown;
	}
	// digital Pad Triangle button Pressure 0 - 255
	if(isTriangleButtonDown) {
		if ([delegate respondsToSelector:@selector(onTriangleButtonWithPressure:)]) {
			//unsigned char PressureTriangle;
			//memcpy( &PressureTriangle, &data[22], sizeof( unsigned char ) );
			[delegate onTriangleButtonWithPressure:(NSInteger)data[22]];
		}
	}
	// digital Pad Circle button Trigger
	if(isCircleButtonDown != preIsCircleButtonDown) {
		if (!isCircleButtonDown && [delegate respondsToSelector:@selector(onCircleButtonWithPressure:)]) {
			[delegate onCircleButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onCircleButton:)]) {
			[delegate onCircleButton:isCircleButtonDown];
		}
		preIsCircleButtonDown = isCircleButtonDown;
	}
	// digital Pad Circle button Pressure 0 - 255
	if(isCircleButtonDown) {
		if ([delegate respondsToSelector:@selector(onCircleButtonWithPressure:)]) {
			//unsigned char PressureCircle;
			//memcpy( &PressureCircle, &data[23], sizeof( unsigned char ) );
			[delegate onCircleButtonWithPressure:(NSInteger)data[23]];
		}
	}
	
	// Cross Button
	// digital Pad Cross button Trigger
	if(isCrossButtonDown != preIsCrossButtonDown) {
		if (!isCrossButtonDown && [delegate respondsToSelector:@selector(onCrossButtonWithPressure:)]) {
			[delegate onCrossButtonWithPressure:0];
		}		
		if ([delegate respondsToSelector:@selector(onCrossButton:)]) {
			[delegate onCrossButton:isCrossButtonDown];
		}
		preIsCrossButtonDown = isCrossButtonDown;
	}
	// digital Pad Cross button Pressure 0 - 255	
	if(isCrossButtonDown) {
		if ([delegate respondsToSelector:@selector(onCrossButtonWithPressure:)]) {
			//unsigned char PressureCross;
			//memcpy( &PressureCross, &data[24], sizeof( unsigned char ) );
			[delegate onCrossButtonWithPressure:(NSInteger)data[24]];
		}
	}
	
	// Square Button
	// digital Pad Square button Trigger
	if(isSquareButtonDown != preIsSquareButtonDown) {
		if (!isSquareButtonDown && [delegate respondsToSelector:@selector(onSquareButtonWithPressure:)]) {
			[delegate onSquareButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onSquareButton:)]) {
			[delegate onSquareButton:isSquareButtonDown];
		}
		preIsSquareButtonDown = isSquareButtonDown;
	}
	// digital Pad Square button Pressure 0 - 255
	if(isSquareButtonDown) {
		if ([delegate respondsToSelector:@selector(onSquareButtonWithPressure:)]) {
			//unsigned char PressureSquare;
			//memcpy( &PressureSquare, &data[25], sizeof( unsigned char ) );
			[delegate onSquareButtonWithPressure:(NSInteger)data[25]];
		}
	}
	
	// L2 Button
	// digital Pad L2 button Trigger
	if(isL2ButtonDown != preIsL2ButtonDown) {
		if (!isL2ButtonDown && [delegate respondsToSelector:@selector(onL2ButtonWithPressure:)]) {
			[delegate onL2ButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onL2Button:)]) {
			[delegate onL2Button:isL2ButtonDown];
		}
		preIsL2ButtonDown = isL2ButtonDown;
	}
	// digital Pad L2 button Pressure 0 - 255
	if(isL2ButtonDown) {
		if ([delegate respondsToSelector:@selector(onL2ButtonWithPressure:)]) {
			//unsigned char PressureL2;
			//memcpy( &PressureL2, &data[18], sizeof( unsigned char ) );
			[delegate onL2ButtonWithPressure:(NSInteger)data[18]];
		}
	}
	
	// R2 Button
	// digital Pad R2 button Trigger
	if(isR2ButtonDown != preIsR2ButtonDown) {
		if (!isR2ButtonDown && [delegate respondsToSelector:@selector(onR2ButtonWithPressure:)]) {
			[delegate onR2ButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onR2Button:)]) {
			[delegate onR2Button:isR2ButtonDown];
		}
		preIsR2ButtonDown = isR2ButtonDown;
	}
	// digital Pad R2 button Pressure 0 - 255
	if(isR2ButtonDown) {
		if ([delegate respondsToSelector:@selector(onR2ButtonWithPressure:)]) {
			//unsigned char PressureR2;
			//memcpy( &PressureR2, &data[19], sizeof( unsigned char ) );
			[delegate onR2ButtonWithPressure:(NSInteger)data[19]];
		}
	}
	
	// L1 Button
	// digital Pad L1 button Trigger
	if(isL1ButtonDown != preIsL1ButtonDown) {
		if (!isL1ButtonDown && [delegate respondsToSelector:@selector(onL1ButtonWithPressure:)]) {
			[delegate onL1ButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onL1Button:)]) {
			[delegate onL1Button:isL1ButtonDown];
		}
		preIsL1ButtonDown = isL1ButtonDown;
	}
	// digital Pad L1 button Pressure 0 - 255
	if(isL1ButtonDown) {
		if ([delegate respondsToSelector:@selector(onL1ButtonWithPressure:)]) {
			//unsigned char PressureL1;
			//memcpy( &PressureL1, &data[20], sizeof( unsigned char ) );
			[delegate onL1ButtonWithPressure:(NSInteger)data[20]];
		}
	}
	
	// R1 Button
	// digital Pad R1 button Trigger
	if(isR1ButtonDown != preIsR1ButtonDown) {
		if (!isR1ButtonDown && [delegate respondsToSelector:@selector(onR1ButtonWithPressure:)]) {
			[delegate onR1ButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onR1Button:)]) {
			[delegate onR1Button:isR1ButtonDown];
		}
		preIsR1ButtonDown = isR1ButtonDown;
	}
	// digital Pad R1 button Pressure 0 - 255
	if(isR1ButtonDown) {
		if ([delegate respondsToSelector:@selector(onR1ButtonWithPressure:)]) {
			//unsigned char PressureR1;
			//memcpy( &PressureR1, &data[21], sizeof( unsigned char ) );
			[delegate onR1ButtonWithPressure:(NSInteger)data[21]];
		}
	}
	
	// North Button
	// Cross North button Trigger
	if(isNorthButtonDown != preIsNorthButtonDown) {
		if (!isNorthButtonDown && [delegate respondsToSelector:@selector(onNorthButtonWithPressure:)]) {
			[delegate onNorthButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onNorthButton:)]) {
			[delegate onNorthButton:isNorthButtonDown];
		}
		preIsNorthButtonDown = isNorthButtonDown;
	}
	// Cross North button Pressure 0 - 255
	if(isNorthButtonDown) {
		if ([delegate respondsToSelector:@selector(onNorthButtonWithPressure:)]) {
			//unsigned char PressureNorth;
			//memcpy( &PressureNorth, &data[14], sizeof( unsigned char ) );
			[delegate onNorthButtonWithPressure:(NSInteger)data[14]];
		}
	}
	
	// East Button
	// Cross East button Trigger
	if(isEastButtonDown != preIsEastButtonDown) {
		if (!isEastButtonDown && [delegate respondsToSelector:@selector(onEastButtonWithPressure:)]) {
			[delegate onEastButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onEastButton:)]) {
			[delegate onEastButton:isEastButtonDown];
		}
		preIsEastButtonDown = isEastButtonDown;
	}
	// Cross East button Pressure 0 - 255
	if(isEastButtonDown) {
		if ([delegate respondsToSelector:@selector(onEastButtonWithPressure:)]) {
			//unsigned char PressureEast;
			//memcpy( &PressureEast, &data[15], sizeof( unsigned char ) );
			[delegate onEastButtonWithPressure:(NSInteger)data[15]];
		}
	}
	
	// South Button
	// Cross South button Trigger
	if(isSouthButtonDown != preIsSouthButtonDown) {
		if (!isSouthButtonDown && [delegate respondsToSelector:@selector(onSouthButtonWithPressure:)]) {
			[delegate onSouthButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onSouthButton:)]) {
			[delegate onSouthButton:isSouthButtonDown];
		}
		preIsSouthButtonDown = isSouthButtonDown;
	}
	// Cross South button Pressure 0 - 255
	if(isSouthButtonDown) {
		if ([delegate respondsToSelector:@selector(onSouthButtonWithPressure:)]) {
			//unsigned char PressureSouth;
			//memcpy( &PressureSouth, &data[16], sizeof( unsigned char ) );
			[delegate onSouthButtonWithPressure:(NSInteger)data[16]];
		}
	}
	
	// West Button
	// Cross West button Trigger
	if(isWestButtonDown != preIsWestButtonDown) {
		if (!isWestButtonDown && [delegate respondsToSelector:@selector(onWestButtonWithPressure:)]) {
			[delegate onWestButtonWithPressure:0];
		}
		if ([delegate respondsToSelector:@selector(onWestButton:)]) {
			[delegate onWestButton:isWestButtonDown];
		}
		preIsWestButtonDown = isWestButtonDown;
	}
	// Cross West button Pressure 0 - 255
	if(isWestButtonDown) {
		if ([delegate respondsToSelector:@selector(onWestButtonWithPressure:)]) {
			//unsigned char PressureWest;
			//memcpy( &PressureWest, &data[17], sizeof( unsigned char ) );
			[delegate onWestButtonWithPressure:(NSInteger)data[17]];
		}
	}

	// Accelerometers
	mx = data[40] | (data[41] << 8);
	my = data[42] | (data[43] << 8);
	mz = data[44] | (data[45] << 8);

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
