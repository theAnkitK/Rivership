/// A place for pasting source from cupertinos `sheets.dart`.
/// We ignore lints here so that we can copy the code without modification.
library;
// ignore_for_file: type=lint

import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Smoothing factor applied to the device's top padding (which approximates the corner radius)
// to achieve a smoother end to the corner radius animation.  A value of 1.0 would use
// the full top padding. Values less than 1.0 reduce the effective corner radius, improving
// the animation's appearance.  Determined through empirical testing.
const double _kDeviceCornerRadiusSmoothingFactor = 0.9;

// Threshold in logical pixels. If the calculated device corner radius (after applying
// the smoothing factor) is below this value, the corner radius transition animation will
// start from zero. This prevents abrupt transitions for devices with small or negligible
// corner radii.  This value, combined with the smoothing factor, corresponds roughly
// to double the targeted radius of 12.  Determined through testing and visual inspection.
const double _kRoundedDeviceCornersThreshold = 20.0;

final Animatable<double> _kOpacityTween = Tween<double>(begin: 0.0, end: 0.10);

// Amount the sheet in the background scales down. Found by measuring the width
// of the sheet in the background and comparing against the screen width on the
// iOS simulator showing an iPhone 16 pro running iOS 18.0. The scale transition
// will go from a default of 1.0 to 1.0 - _kSheetScaleFactor.
const double _kSheetScaleFactor = 0.0835;

final Animatable<double> _kScaleTween =
    Tween<double>(begin: 1.0, end: 1.0 - _kSheetScaleFactor);

class CopiedCupertinoSheetTransition extends StatefulWidget {
  /// Creates an iOS style sheet transition.
  const CopiedCupertinoSheetTransition({
    super.key,
    required this.primaryRouteAnimation,
    required this.secondaryRouteAnimation,
    required this.child,
    required this.linearTransition,
  });

  /// `primaryRouteAnimation` is a linear route animation from 0.0 to 1.0 when
  /// this screen is being pushed.
  final Animation<double> primaryRouteAnimation;

  /// `secondaryRouteAnimation` is a linear route animation from 0.0 to 1.0 when
  /// another screen is being pushed on top of this one.
  final Animation<double> secondaryRouteAnimation;

  /// The widget below this widget in the tree.
  final Widget child;

  /// Whether to perform the transition linearly.
  ///
  /// Used to respond to a drag gesture.
  final bool linearTransition;

  static double _getRelativeTopPadding(
    BuildContext context, {
    double extraPadding = 0,
    double minFraction = 0.05,
  }) {
    final safeArea = MediaQuery.paddingOf(context);
    final height = MediaQuery.sizeOf(context).height;

    if (height == 0) {
      return minFraction;
    }
    // Ensure that the sheet moves down by at least 5% of the screen height if
    // the safe area is very small (e.g. no notch).
    return max((safeArea.top + extraPadding) / height, minFraction);
  }

  static Color _getOverlayColor(BuildContext context) {
    final bool isDarkMode =
        CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return isDarkMode ? const Color(0xFFc8c8c8) : const Color(0xFF000000);
  }

  /// The primary delegated transition. Will slide a non [CupertinoSheetRoute] page down.
  ///
  /// Provided to the previous route to coordinate transitions between routes.
  ///
  /// If a [CupertinoSheetRoute] already exists in the stack, then it will
  /// slide the previous sheet upwards instead.
  static Widget? delegateTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    final Animatable<Offset> topDownTween = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(
        0,
        _getRelativeTopPadding(context),
      ),
    );

    final double deviceCornerRadius =
        (MediaQuery.maybeViewPaddingOf(context)?.top ?? 0) *
            _kDeviceCornerRadiusSmoothingFactor;
    final bool roundedDeviceCorners =
        deviceCornerRadius > _kRoundedDeviceCornersThreshold;

    final Animatable<BorderRadiusGeometry> decorationTween =
        Tween<BorderRadiusGeometry>(
      begin: BorderRadius.vertical(
        top: Radius.circular(roundedDeviceCorners ? deviceCornerRadius : 0),
      ),
      end: BorderRadius.circular(8),
    );

    final Animation<BorderRadiusGeometry> radiusAnimation =
        secondaryAnimation.drive(decorationTween);

    final Animation<Offset> slideAnimation =
        secondaryAnimation.drive(topDownTween);
    final Animation<double> scaleAnimation =
        secondaryAnimation.drive(_kScaleTween);

    final Widget? contrastedChild =
        _getOverlayedChild(context, child, secondaryAnimation);

    final double topGapHeight =
        MediaQuery.sizeOf(context).height * _getRelativeTopPadding(context);

    return Stack(
      children: <Widget>[
        AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarBrightness: Brightness.dark,
            statusBarIconBrightness: Brightness.light,
          ),
          child: SizedBox(height: topGapHeight, width: double.infinity),
        ),
        SlideTransition(
          position: slideAnimation,
          child: ScaleTransition(
            scale: scaleAnimation,
            filterQuality: FilterQuality.medium,
            alignment: Alignment.topCenter,
            child: AnimatedBuilder(
              animation: radiusAnimation,
              child: child,
              builder: (BuildContext context, Widget? child) {
                return ClipRSuperellipse(
                  borderRadius: !secondaryAnimation.isDismissed
                      ? radiusAnimation.value
                      : BorderRadius.circular(0),
                  child: contrastedChild,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static Widget? _getOverlayedChild(
    BuildContext context,
    Widget? child,
    Animation<double> animation,
  ) {
    final opacity = animation.drive(_kOpacityTween);

    final Color overlayColor =
        CopiedCupertinoSheetTransition._getOverlayColor(context);

    return Stack(
      children: <Widget>[
        if (child != null) child,
        IgnorePointer(
          child: FadeTransition(
            opacity: opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(color: overlayColor),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  State<CopiedCupertinoSheetTransition> createState() =>
      _CupertinoSheetTransitionState();
}

class _CupertinoSheetTransitionState
    extends State<CopiedCupertinoSheetTransition> {
  CurvedAnimation? _primaryPositionCurve;

  // The offset animation when this page is being covered by another sheet.
  late Animation<Offset> _secondaryPositionAnimation;

  // The scale animation when this page is being covered by another sheet.
  late Animation<double> _secondaryScaleAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disposeCurve();
    _setupAnimation();
  }

  @override
  void didUpdateWidget(covariant CopiedCupertinoSheetTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryRouteAnimation != widget.primaryRouteAnimation ||
        oldWidget.secondaryRouteAnimation != widget.secondaryRouteAnimation) {
      _disposeCurve();
      _setupAnimation();
    }
  }

  @override
  void dispose() {
    _disposeCurve();
    super.dispose();
  }

  void _setupAnimation() {
    _primaryPositionCurve = CurvedAnimation(
      curve: Curves.fastEaseInToSlowEaseOut,
      reverseCurve: Curves.fastEaseInToSlowEaseOut.flipped,
      parent: widget.primaryRouteAnimation,
    );

    _secondaryPositionAnimation = widget.secondaryRouteAnimation.drive(
      Tween<Offset>(
        begin: Offset(0, 0),
        end: Offset(
          0,
          -CopiedCupertinoSheetTransition._getRelativeTopPadding(
            context,
            extraPadding: 16,
            minFraction: 0.0,
          ),
        ),
      ),
    );

    _secondaryScaleAnimation =
        widget.secondaryRouteAnimation.drive(_kScaleTween);
  }

  void _disposeCurve() {
    _primaryPositionCurve?.dispose();
    _primaryPositionCurve = null;
  }

  Widget _coverSheetPrimaryTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget? child,
  ) {
    final Animatable<Offset> offsetTween = Tween<Offset>(
      begin: Offset(0, 1),
      end: Offset(0, 0),
    );

    final radiusTween = BorderRadiusTween(
      begin: BorderRadius.circular(12),
      end: BorderRadius.circular(8),
    );

    final Animation<Offset> positionAnimation = animation.drive(offsetTween);

    return SlideTransition(
      position: positionAnimation,
      child: ValueListenableBuilder(
        valueListenable: secondaryAnimation.drive(radiusTween),
        builder: (context, value, child) {
          return ClipRSuperellipse(
            borderRadius: value!,
            child: child,
          );
        },
        child: child,
      ),
    );
  }

  Widget _coverSheetSecondaryTransition(
      Animation<double> secondaryAnimation, Widget? child) {
    return SlideTransition(
      position: _secondaryPositionAnimation,
      transformHitTests: false,
      child: ScaleTransition(
        scale: _secondaryScaleAnimation,
        filterQuality: FilterQuality.medium,
        alignment: Alignment.topCenter,
        child: CopiedCupertinoSheetTransition._getOverlayedChild(
          context,
          child,
          secondaryAnimation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      left: false,
      right: false,
      bottom: false,
      minimum: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.05),
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SizedBox.expand(
          child: _coverSheetSecondaryTransition(
            widget.secondaryRouteAnimation,
            _coverSheetPrimaryTransition(
              context,
              widget.primaryRouteAnimation,
              widget.secondaryRouteAnimation,
              widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// Internally used to see if another sheet is in the tree already.
@internal
class StupidCupertinoSheetScope extends InheritedWidget {
  const StupidCupertinoSheetScope({required super.child});

  static StupidCupertinoSheetScope? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<StupidCupertinoSheetScope>();
  }

  @override
  bool updateShouldNotify(StupidCupertinoSheetScope oldWidget) => false;
}
