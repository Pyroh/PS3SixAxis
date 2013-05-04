PS3SixAxis
==========

Simple library to use PS3 Controller in Cocoa.

HOW TO USE?
===========

Add IOKit.framework, IOBluetooth.framework and libPS3SixAxis.a to your Xcode project's Frameworks and Libraries.
Make sure you have PS3SixAxis.h in /usr/local/include or your own custom include path.

Then import the PS3SixAxis.h header.

	#import <PS3SixAxis.h>
Add PS3SixAxisDelegate to your controller delegates and a PS3SixAxis object.

	@interface YourSixAxisController : NSObject <PS3SixAxisDelegate> {
		PS3SixAxis *ps3SixAxis;
	}
Init the PS3SixAxis object with the controller itself as delegate.

	ps3SixAxis = [PS3SixAxis sixAixisControllerWithDelegate:self];
	[ps3SixAxis connect:YES];
And then implement the delegates methods you need.


SCREENSHOTS (PS3SixAxisTest)
============================

[![](http://imageshack.us/a/img407/1748/20130504at124949.png)](http://imageshack.us/a/img407/1748/20130504at124949.png)
[![](http://imageshack.us/a/img542/5142/20130504at124802.png)](http://imageshack.us/a/img542/5142/20130504at124802.png)

