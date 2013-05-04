//
//  SixAxisStick.m
//  PS3_SixAxis
//
//  Created by Tobias Wetzel on 11.05.10.
//  Copyright 2010 Outcut. All rights reserved.
//

#import "SixAxisStick.h"


@implementation SixAxisStick

- (id) initWithFrame:(NSRect)frameRect {
	if(self = [super initWithFrame:frameRect]) {
		[self setWantsLayer:YES];
		
		CGColorRef backColor = CGColorCreateGenericRGB(1.00f, 1.00f, 1.00f, 0.00f);
		
		point = [CALayer layer];
        [point setBounds:CGRectMake(0, 0, 40, 40)];
		[point setAnchorPoint:CGPointMake(0, 0)];
		[point setShadowOpacity:.8f];
		[point setCornerRadius:20];
		[[self layer] setBackgroundColor:backColor];
		[[self layer] addSublayer:point];
		
		[self setJoyStickX:128 Y:128 pressed:NO];
	}
	return self;
}

- (void) setJoyStickX:(NSInteger)x Y:(NSInteger)y pressed:(BOOL)isPressed {
	NSSize size = [self frame].size;
	float scale = size.width / (255 + 20);
	CGColorRef pointColor;
	if (isPressed) {
		pointColor = CGColorCreateGenericRGB(1.00f, 0.00f, 0.00f, 1.00f);
	} else {
		pointColor = CGColorCreateGenericRGB(0.25f, 0.25f, 0.25f, 1.00f);
	}
	[point setBackgroundColor:pointColor];
	[point setPosition:CGPointMake(x * scale - 20, size.height - (y * scale) - 20)];
}

@end
