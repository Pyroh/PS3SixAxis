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
        [[self layer] setMasksToBounds:NO];
		
		CGColorRef backColor = CGColorCreateGenericRGB(1.00f, 1.00f, 1.00f, 0.00f);
		
		point = [CALayer layer];
        [point setBounds:CGRectMake(0, 0, frameRect.size.width*0.65, frameRect.size.height*0.65)];
        [point setMasksToBounds:NO];
		[point setAnchorPoint:CGPointMake(0.5, 0.5)];
		[point setShadowOpacity:.8f];
		[point setCornerRadius:frameRect.size.width*0.325];
		[[self layer] setBackgroundColor:backColor];
		[[self layer] addSublayer:point];
        		
		[self setJoyStickX:128 Y:128 pressed:NO];
	}
	return self;
}

- (void) setJoyStickX:(NSInteger)x Y:(NSInteger)y pressed:(BOOL)isPressed {
	NSSize size = [self frame].size;
	float scale = (size.width-2.0) / 255.0;
	CGColorRef pointColor;
	if (isPressed) {
		pointColor = CGColorCreateGenericRGB(1.00f, 0.00f, 0.00f, 1.00f);
	} else {
		pointColor = CGColorCreateGenericRGB(0.236, 0.236, 0.236, 1.00f);
	}
	[point setBackgroundColor:pointColor];
	[point setPosition:CGPointMake(x * scale + 1.0, size.height - (y * scale) + 1.0)];
}

- (void) drawRect:(NSRect)dirtyRect {

    NSColor* blackColor = [NSColor colorWithCalibratedRed: 0 green: 0 blue: 0 alpha: 1];
    NSColor* greyColor = [NSColor colorWithCalibratedRed: 0.151 green: 0.151 blue: 0.151 alpha: 1];
    
    {
        NSBezierPath* border = [NSBezierPath bezierPathWithOvalInRect:CGRectMake(1.0, 1.0, dirtyRect.size.width-2.0, dirtyRect.size.height-2.0)];
        [greyColor setFill];
        [border fill];
        [blackColor setStroke];
        [border setLineWidth: 1];
        [border stroke];
        
        NSBezierPath* blackpart = [NSBezierPath bezierPathWithOvalInRect:CGRectMake(17.0, 17.0, dirtyRect.size.width-34.0, dirtyRect.size.height-34.0)];
        [blackColor setFill];
        [blackpart fill];
    }

}

@end
