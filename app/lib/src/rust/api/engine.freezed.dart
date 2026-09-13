// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'engine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MediaAction {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MediaAction()';
}


}

/// @nodoc
class $MediaActionCopyWith<$Res>  {
$MediaActionCopyWith(MediaAction _, $Res Function(MediaAction) __);
}


/// Adds pattern-matching-related methods to [MediaAction].
extension MediaActionPatterns on MediaAction {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MediaAction_Play value)?  play,TResult Function( MediaAction_Pause value)?  pause,TResult Function( MediaAction_Toggle value)?  toggle,TResult Function( MediaAction_Next value)?  next,TResult Function( MediaAction_Previous value)?  previous,TResult Function( MediaAction_Stop value)?  stop,TResult Function( MediaAction_SeekTo value)?  seekTo,TResult Function( MediaAction_SeekBy value)?  seekBy,TResult Function( MediaAction_SetVolume value)?  setVolume,TResult Function( MediaAction_Raise value)?  raise,TResult Function( MediaAction_Quit value)?  quit,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MediaAction_Play() when play != null:
return play(_that);case MediaAction_Pause() when pause != null:
return pause(_that);case MediaAction_Toggle() when toggle != null:
return toggle(_that);case MediaAction_Next() when next != null:
return next(_that);case MediaAction_Previous() when previous != null:
return previous(_that);case MediaAction_Stop() when stop != null:
return stop(_that);case MediaAction_SeekTo() when seekTo != null:
return seekTo(_that);case MediaAction_SeekBy() when seekBy != null:
return seekBy(_that);case MediaAction_SetVolume() when setVolume != null:
return setVolume(_that);case MediaAction_Raise() when raise != null:
return raise(_that);case MediaAction_Quit() when quit != null:
return quit(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MediaAction_Play value)  play,required TResult Function( MediaAction_Pause value)  pause,required TResult Function( MediaAction_Toggle value)  toggle,required TResult Function( MediaAction_Next value)  next,required TResult Function( MediaAction_Previous value)  previous,required TResult Function( MediaAction_Stop value)  stop,required TResult Function( MediaAction_SeekTo value)  seekTo,required TResult Function( MediaAction_SeekBy value)  seekBy,required TResult Function( MediaAction_SetVolume value)  setVolume,required TResult Function( MediaAction_Raise value)  raise,required TResult Function( MediaAction_Quit value)  quit,}){
final _that = this;
switch (_that) {
case MediaAction_Play():
return play(_that);case MediaAction_Pause():
return pause(_that);case MediaAction_Toggle():
return toggle(_that);case MediaAction_Next():
return next(_that);case MediaAction_Previous():
return previous(_that);case MediaAction_Stop():
return stop(_that);case MediaAction_SeekTo():
return seekTo(_that);case MediaAction_SeekBy():
return seekBy(_that);case MediaAction_SetVolume():
return setVolume(_that);case MediaAction_Raise():
return raise(_that);case MediaAction_Quit():
return quit(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MediaAction_Play value)?  play,TResult? Function( MediaAction_Pause value)?  pause,TResult? Function( MediaAction_Toggle value)?  toggle,TResult? Function( MediaAction_Next value)?  next,TResult? Function( MediaAction_Previous value)?  previous,TResult? Function( MediaAction_Stop value)?  stop,TResult? Function( MediaAction_SeekTo value)?  seekTo,TResult? Function( MediaAction_SeekBy value)?  seekBy,TResult? Function( MediaAction_SetVolume value)?  setVolume,TResult? Function( MediaAction_Raise value)?  raise,TResult? Function( MediaAction_Quit value)?  quit,}){
final _that = this;
switch (_that) {
case MediaAction_Play() when play != null:
return play(_that);case MediaAction_Pause() when pause != null:
return pause(_that);case MediaAction_Toggle() when toggle != null:
return toggle(_that);case MediaAction_Next() when next != null:
return next(_that);case MediaAction_Previous() when previous != null:
return previous(_that);case MediaAction_Stop() when stop != null:
return stop(_that);case MediaAction_SeekTo() when seekTo != null:
return seekTo(_that);case MediaAction_SeekBy() when seekBy != null:
return seekBy(_that);case MediaAction_SetVolume() when setVolume != null:
return setVolume(_that);case MediaAction_Raise() when raise != null:
return raise(_that);case MediaAction_Quit() when quit != null:
return quit(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  play,TResult Function()?  pause,TResult Function()?  toggle,TResult Function()?  next,TResult Function()?  previous,TResult Function()?  stop,TResult Function( PlatformInt64 positionMs)?  seekTo,TResult Function( PlatformInt64 deltaMs)?  seekBy,TResult Function( double volume)?  setVolume,TResult Function()?  raise,TResult Function()?  quit,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MediaAction_Play() when play != null:
return play();case MediaAction_Pause() when pause != null:
return pause();case MediaAction_Toggle() when toggle != null:
return toggle();case MediaAction_Next() when next != null:
return next();case MediaAction_Previous() when previous != null:
return previous();case MediaAction_Stop() when stop != null:
return stop();case MediaAction_SeekTo() when seekTo != null:
return seekTo(_that.positionMs);case MediaAction_SeekBy() when seekBy != null:
return seekBy(_that.deltaMs);case MediaAction_SetVolume() when setVolume != null:
return setVolume(_that.volume);case MediaAction_Raise() when raise != null:
return raise();case MediaAction_Quit() when quit != null:
return quit();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  play,required TResult Function()  pause,required TResult Function()  toggle,required TResult Function()  next,required TResult Function()  previous,required TResult Function()  stop,required TResult Function( PlatformInt64 positionMs)  seekTo,required TResult Function( PlatformInt64 deltaMs)  seekBy,required TResult Function( double volume)  setVolume,required TResult Function()  raise,required TResult Function()  quit,}) {final _that = this;
switch (_that) {
case MediaAction_Play():
return play();case MediaAction_Pause():
return pause();case MediaAction_Toggle():
return toggle();case MediaAction_Next():
return next();case MediaAction_Previous():
return previous();case MediaAction_Stop():
return stop();case MediaAction_SeekTo():
return seekTo(_that.positionMs);case MediaAction_SeekBy():
return seekBy(_that.deltaMs);case MediaAction_SetVolume():
return setVolume(_that.volume);case MediaAction_Raise():
return raise();case MediaAction_Quit():
return quit();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  play,TResult? Function()?  pause,TResult? Function()?  toggle,TResult? Function()?  next,TResult? Function()?  previous,TResult? Function()?  stop,TResult? Function( PlatformInt64 positionMs)?  seekTo,TResult? Function( PlatformInt64 deltaMs)?  seekBy,TResult? Function( double volume)?  setVolume,TResult? Function()?  raise,TResult? Function()?  quit,}) {final _that = this;
switch (_that) {
case MediaAction_Play() when play != null:
return play();case MediaAction_Pause() when pause != null:
return pause();case MediaAction_Toggle() when toggle != null:
return toggle();case MediaAction_Next() when next != null:
return next();case MediaAction_Previous() when previous != null:
return previous();case MediaAction_Stop() when stop != null:
return stop();case MediaAction_SeekTo() when seekTo != null:
return seekTo(_that.positionMs);case MediaAction_SeekBy() when seekBy != null:
return seekBy(_that.deltaMs);case MediaAction_SetVolume() when setVolume != null:
return setVolume(_that.volume);case MediaAction_Raise() when raise != null:
return raise();case MediaAction_Quit() when quit != null:
return quit();case _:
  return null;

}
}

}

/// @nodoc


class MediaAction_Play extends MediaAction {
  const MediaAction_Play(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_Play);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MediaAction.play()';
}


}




/// @nodoc


class MediaAction_Pause extends MediaAction {
  const MediaAction_Pause(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_Pause);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MediaAction.pause()';
}


}




/// @nodoc


class MediaAction_Toggle extends MediaAction {
  const MediaAction_Toggle(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_Toggle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MediaAction.toggle()';
}


}




/// @nodoc


class MediaAction_Next extends MediaAction {
  const MediaAction_Next(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_Next);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MediaAction.next()';
}


}




/// @nodoc


class MediaAction_Previous extends MediaAction {
  const MediaAction_Previous(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_Previous);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MediaAction.previous()';
}


}




/// @nodoc


class MediaAction_Stop extends MediaAction {
  const MediaAction_Stop(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_Stop);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MediaAction.stop()';
}


}




/// @nodoc


class MediaAction_SeekTo extends MediaAction {
  const MediaAction_SeekTo({required this.positionMs}): super._();
  

 final  PlatformInt64 positionMs;

/// Create a copy of MediaAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaAction_SeekToCopyWith<MediaAction_SeekTo> get copyWith => _$MediaAction_SeekToCopyWithImpl<MediaAction_SeekTo>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_SeekTo&&(identical(other.positionMs, positionMs) || other.positionMs == positionMs));
}


@override
int get hashCode => Object.hash(runtimeType,positionMs);

@override
String toString() {
  return 'MediaAction.seekTo(positionMs: $positionMs)';
}


}

/// @nodoc
abstract mixin class $MediaAction_SeekToCopyWith<$Res> implements $MediaActionCopyWith<$Res> {
  factory $MediaAction_SeekToCopyWith(MediaAction_SeekTo value, $Res Function(MediaAction_SeekTo) _then) = _$MediaAction_SeekToCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 positionMs
});




}
/// @nodoc
class _$MediaAction_SeekToCopyWithImpl<$Res>
    implements $MediaAction_SeekToCopyWith<$Res> {
  _$MediaAction_SeekToCopyWithImpl(this._self, this._then);

  final MediaAction_SeekTo _self;
  final $Res Function(MediaAction_SeekTo) _then;

/// Create a copy of MediaAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? positionMs = null,}) {
  return _then(MediaAction_SeekTo(
positionMs: null == positionMs ? _self.positionMs : positionMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class MediaAction_SeekBy extends MediaAction {
  const MediaAction_SeekBy({required this.deltaMs}): super._();
  

 final  PlatformInt64 deltaMs;

/// Create a copy of MediaAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaAction_SeekByCopyWith<MediaAction_SeekBy> get copyWith => _$MediaAction_SeekByCopyWithImpl<MediaAction_SeekBy>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_SeekBy&&(identical(other.deltaMs, deltaMs) || other.deltaMs == deltaMs));
}


@override
int get hashCode => Object.hash(runtimeType,deltaMs);

@override
String toString() {
  return 'MediaAction.seekBy(deltaMs: $deltaMs)';
}


}

/// @nodoc
abstract mixin class $MediaAction_SeekByCopyWith<$Res> implements $MediaActionCopyWith<$Res> {
  factory $MediaAction_SeekByCopyWith(MediaAction_SeekBy value, $Res Function(MediaAction_SeekBy) _then) = _$MediaAction_SeekByCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 deltaMs
});




}
/// @nodoc
class _$MediaAction_SeekByCopyWithImpl<$Res>
    implements $MediaAction_SeekByCopyWith<$Res> {
  _$MediaAction_SeekByCopyWithImpl(this._self, this._then);

  final MediaAction_SeekBy _self;
  final $Res Function(MediaAction_SeekBy) _then;

/// Create a copy of MediaAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deltaMs = null,}) {
  return _then(MediaAction_SeekBy(
deltaMs: null == deltaMs ? _self.deltaMs : deltaMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class MediaAction_SetVolume extends MediaAction {
  const MediaAction_SetVolume({required this.volume}): super._();
  

 final  double volume;

/// Create a copy of MediaAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaAction_SetVolumeCopyWith<MediaAction_SetVolume> get copyWith => _$MediaAction_SetVolumeCopyWithImpl<MediaAction_SetVolume>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_SetVolume&&(identical(other.volume, volume) || other.volume == volume));
}


@override
int get hashCode => Object.hash(runtimeType,volume);

@override
String toString() {
  return 'MediaAction.setVolume(volume: $volume)';
}


}

/// @nodoc
abstract mixin class $MediaAction_SetVolumeCopyWith<$Res> implements $MediaActionCopyWith<$Res> {
  factory $MediaAction_SetVolumeCopyWith(MediaAction_SetVolume value, $Res Function(MediaAction_SetVolume) _then) = _$MediaAction_SetVolumeCopyWithImpl;
@useResult
$Res call({
 double volume
});




}
/// @nodoc
class _$MediaAction_SetVolumeCopyWithImpl<$Res>
    implements $MediaAction_SetVolumeCopyWith<$Res> {
  _$MediaAction_SetVolumeCopyWithImpl(this._self, this._then);

  final MediaAction_SetVolume _self;
  final $Res Function(MediaAction_SetVolume) _then;

/// Create a copy of MediaAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? volume = null,}) {
  return _then(MediaAction_SetVolume(
volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class MediaAction_Raise extends MediaAction {
  const MediaAction_Raise(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_Raise);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MediaAction.raise()';
}


}




/// @nodoc


class MediaAction_Quit extends MediaAction {
  const MediaAction_Quit(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaAction_Quit);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MediaAction.quit()';
}


}




/// @nodoc
mixin _$PlayerEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PlayerEvent()';
}


}

/// @nodoc
class $PlayerEventCopyWith<$Res>  {
$PlayerEventCopyWith(PlayerEvent _, $Res Function(PlayerEvent) __);
}


/// Adds pattern-matching-related methods to [PlayerEvent].
extension PlayerEventPatterns on PlayerEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PlayerEvent_TrackStarted value)?  trackStarted,TResult Function( PlayerEvent_TrackEnded value)?  trackEnded,TResult Function( PlayerEvent_Position value)?  position,TResult Function( PlayerEvent_State value)?  state,TResult Function( PlayerEvent_MediaControl value)?  mediaControl,TResult Function( PlayerEvent_DeviceChanged value)?  deviceChanged,TResult Function( PlayerEvent_Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted() when trackStarted != null:
return trackStarted(_that);case PlayerEvent_TrackEnded() when trackEnded != null:
return trackEnded(_that);case PlayerEvent_Position() when position != null:
return position(_that);case PlayerEvent_State() when state != null:
return state(_that);case PlayerEvent_MediaControl() when mediaControl != null:
return mediaControl(_that);case PlayerEvent_DeviceChanged() when deviceChanged != null:
return deviceChanged(_that);case PlayerEvent_Error() when error != null:
return error(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PlayerEvent_TrackStarted value)  trackStarted,required TResult Function( PlayerEvent_TrackEnded value)  trackEnded,required TResult Function( PlayerEvent_Position value)  position,required TResult Function( PlayerEvent_State value)  state,required TResult Function( PlayerEvent_MediaControl value)  mediaControl,required TResult Function( PlayerEvent_DeviceChanged value)  deviceChanged,required TResult Function( PlayerEvent_Error value)  error,}){
final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted():
return trackStarted(_that);case PlayerEvent_TrackEnded():
return trackEnded(_that);case PlayerEvent_Position():
return position(_that);case PlayerEvent_State():
return state(_that);case PlayerEvent_MediaControl():
return mediaControl(_that);case PlayerEvent_DeviceChanged():
return deviceChanged(_that);case PlayerEvent_Error():
return error(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PlayerEvent_TrackStarted value)?  trackStarted,TResult? Function( PlayerEvent_TrackEnded value)?  trackEnded,TResult? Function( PlayerEvent_Position value)?  position,TResult? Function( PlayerEvent_State value)?  state,TResult? Function( PlayerEvent_MediaControl value)?  mediaControl,TResult? Function( PlayerEvent_DeviceChanged value)?  deviceChanged,TResult? Function( PlayerEvent_Error value)?  error,}){
final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted() when trackStarted != null:
return trackStarted(_that);case PlayerEvent_TrackEnded() when trackEnded != null:
return trackEnded(_that);case PlayerEvent_Position() when position != null:
return position(_that);case PlayerEvent_State() when state != null:
return state(_that);case PlayerEvent_MediaControl() when mediaControl != null:
return mediaControl(_that);case PlayerEvent_DeviceChanged() when deviceChanged != null:
return deviceChanged(_that);case PlayerEvent_Error() when error != null:
return error(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id)?  trackStarted,TResult Function( String id,  String? error)?  trackEnded,TResult Function( String id,  PlatformInt64 positionMs,  PlatformInt64? durationMs,  double? buffered)?  position,TResult Function( bool playing,  bool buffering,  bool hasTrack)?  state,TResult Function( MediaAction action)?  mediaControl,TResult Function( String name,  int sampleRate)?  deviceChanged,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted() when trackStarted != null:
return trackStarted(_that.id);case PlayerEvent_TrackEnded() when trackEnded != null:
return trackEnded(_that.id,_that.error);case PlayerEvent_Position() when position != null:
return position(_that.id,_that.positionMs,_that.durationMs,_that.buffered);case PlayerEvent_State() when state != null:
return state(_that.playing,_that.buffering,_that.hasTrack);case PlayerEvent_MediaControl() when mediaControl != null:
return mediaControl(_that.action);case PlayerEvent_DeviceChanged() when deviceChanged != null:
return deviceChanged(_that.name,_that.sampleRate);case PlayerEvent_Error() when error != null:
return error(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id)  trackStarted,required TResult Function( String id,  String? error)  trackEnded,required TResult Function( String id,  PlatformInt64 positionMs,  PlatformInt64? durationMs,  double? buffered)  position,required TResult Function( bool playing,  bool buffering,  bool hasTrack)  state,required TResult Function( MediaAction action)  mediaControl,required TResult Function( String name,  int sampleRate)  deviceChanged,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted():
return trackStarted(_that.id);case PlayerEvent_TrackEnded():
return trackEnded(_that.id,_that.error);case PlayerEvent_Position():
return position(_that.id,_that.positionMs,_that.durationMs,_that.buffered);case PlayerEvent_State():
return state(_that.playing,_that.buffering,_that.hasTrack);case PlayerEvent_MediaControl():
return mediaControl(_that.action);case PlayerEvent_DeviceChanged():
return deviceChanged(_that.name,_that.sampleRate);case PlayerEvent_Error():
return error(_that.message);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id)?  trackStarted,TResult? Function( String id,  String? error)?  trackEnded,TResult? Function( String id,  PlatformInt64 positionMs,  PlatformInt64? durationMs,  double? buffered)?  position,TResult? Function( bool playing,  bool buffering,  bool hasTrack)?  state,TResult? Function( MediaAction action)?  mediaControl,TResult? Function( String name,  int sampleRate)?  deviceChanged,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted() when trackStarted != null:
return trackStarted(_that.id);case PlayerEvent_TrackEnded() when trackEnded != null:
return trackEnded(_that.id,_that.error);case PlayerEvent_Position() when position != null:
return position(_that.id,_that.positionMs,_that.durationMs,_that.buffered);case PlayerEvent_State() when state != null:
return state(_that.playing,_that.buffering,_that.hasTrack);case PlayerEvent_MediaControl() when mediaControl != null:
return mediaControl(_that.action);case PlayerEvent_DeviceChanged() when deviceChanged != null:
return deviceChanged(_that.name,_that.sampleRate);case PlayerEvent_Error() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class PlayerEvent_TrackStarted extends PlayerEvent {
  const PlayerEvent_TrackStarted({required this.id}): super._();
  

 final  String id;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_TrackStartedCopyWith<PlayerEvent_TrackStarted> get copyWith => _$PlayerEvent_TrackStartedCopyWithImpl<PlayerEvent_TrackStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_TrackStarted&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'PlayerEvent.trackStarted(id: $id)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_TrackStartedCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_TrackStartedCopyWith(PlayerEvent_TrackStarted value, $Res Function(PlayerEvent_TrackStarted) _then) = _$PlayerEvent_TrackStartedCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$PlayerEvent_TrackStartedCopyWithImpl<$Res>
    implements $PlayerEvent_TrackStartedCopyWith<$Res> {
  _$PlayerEvent_TrackStartedCopyWithImpl(this._self, this._then);

  final PlayerEvent_TrackStarted _self;
  final $Res Function(PlayerEvent_TrackStarted) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(PlayerEvent_TrackStarted(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PlayerEvent_TrackEnded extends PlayerEvent {
  const PlayerEvent_TrackEnded({required this.id, this.error}): super._();
  

 final  String id;
 final  String? error;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_TrackEndedCopyWith<PlayerEvent_TrackEnded> get copyWith => _$PlayerEvent_TrackEndedCopyWithImpl<PlayerEvent_TrackEnded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_TrackEnded&&(identical(other.id, id) || other.id == id)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,id,error);

@override
String toString() {
  return 'PlayerEvent.trackEnded(id: $id, error: $error)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_TrackEndedCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_TrackEndedCopyWith(PlayerEvent_TrackEnded value, $Res Function(PlayerEvent_TrackEnded) _then) = _$PlayerEvent_TrackEndedCopyWithImpl;
@useResult
$Res call({
 String id, String? error
});




}
/// @nodoc
class _$PlayerEvent_TrackEndedCopyWithImpl<$Res>
    implements $PlayerEvent_TrackEndedCopyWith<$Res> {
  _$PlayerEvent_TrackEndedCopyWithImpl(this._self, this._then);

  final PlayerEvent_TrackEnded _self;
  final $Res Function(PlayerEvent_TrackEnded) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? error = freezed,}) {
  return _then(PlayerEvent_TrackEnded(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class PlayerEvent_Position extends PlayerEvent {
  const PlayerEvent_Position({required this.id, required this.positionMs, this.durationMs, this.buffered}): super._();
  

 final  String id;
 final  PlatformInt64 positionMs;
 final  PlatformInt64? durationMs;
 final  double? buffered;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_PositionCopyWith<PlayerEvent_Position> get copyWith => _$PlayerEvent_PositionCopyWithImpl<PlayerEvent_Position>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_Position&&(identical(other.id, id) || other.id == id)&&(identical(other.positionMs, positionMs) || other.positionMs == positionMs)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.buffered, buffered) || other.buffered == buffered));
}


@override
int get hashCode => Object.hash(runtimeType,id,positionMs,durationMs,buffered);

@override
String toString() {
  return 'PlayerEvent.position(id: $id, positionMs: $positionMs, durationMs: $durationMs, buffered: $buffered)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_PositionCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_PositionCopyWith(PlayerEvent_Position value, $Res Function(PlayerEvent_Position) _then) = _$PlayerEvent_PositionCopyWithImpl;
@useResult
$Res call({
 String id, PlatformInt64 positionMs, PlatformInt64? durationMs, double? buffered
});




}
/// @nodoc
class _$PlayerEvent_PositionCopyWithImpl<$Res>
    implements $PlayerEvent_PositionCopyWith<$Res> {
  _$PlayerEvent_PositionCopyWithImpl(this._self, this._then);

  final PlayerEvent_Position _self;
  final $Res Function(PlayerEvent_Position) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? positionMs = null,Object? durationMs = freezed,Object? buffered = freezed,}) {
  return _then(PlayerEvent_Position(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,positionMs: null == positionMs ? _self.positionMs : positionMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64,durationMs: freezed == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,buffered: freezed == buffered ? _self.buffered : buffered // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc


class PlayerEvent_State extends PlayerEvent {
  const PlayerEvent_State({required this.playing, required this.buffering, required this.hasTrack}): super._();
  

 final  bool playing;
 final  bool buffering;
 final  bool hasTrack;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_StateCopyWith<PlayerEvent_State> get copyWith => _$PlayerEvent_StateCopyWithImpl<PlayerEvent_State>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_State&&(identical(other.playing, playing) || other.playing == playing)&&(identical(other.buffering, buffering) || other.buffering == buffering)&&(identical(other.hasTrack, hasTrack) || other.hasTrack == hasTrack));
}


@override
int get hashCode => Object.hash(runtimeType,playing,buffering,hasTrack);

@override
String toString() {
  return 'PlayerEvent.state(playing: $playing, buffering: $buffering, hasTrack: $hasTrack)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_StateCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_StateCopyWith(PlayerEvent_State value, $Res Function(PlayerEvent_State) _then) = _$PlayerEvent_StateCopyWithImpl;
@useResult
$Res call({
 bool playing, bool buffering, bool hasTrack
});




}
/// @nodoc
class _$PlayerEvent_StateCopyWithImpl<$Res>
    implements $PlayerEvent_StateCopyWith<$Res> {
  _$PlayerEvent_StateCopyWithImpl(this._self, this._then);

  final PlayerEvent_State _self;
  final $Res Function(PlayerEvent_State) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? playing = null,Object? buffering = null,Object? hasTrack = null,}) {
  return _then(PlayerEvent_State(
playing: null == playing ? _self.playing : playing // ignore: cast_nullable_to_non_nullable
as bool,buffering: null == buffering ? _self.buffering : buffering // ignore: cast_nullable_to_non_nullable
as bool,hasTrack: null == hasTrack ? _self.hasTrack : hasTrack // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class PlayerEvent_MediaControl extends PlayerEvent {
  const PlayerEvent_MediaControl({required this.action}): super._();
  

 final  MediaAction action;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_MediaControlCopyWith<PlayerEvent_MediaControl> get copyWith => _$PlayerEvent_MediaControlCopyWithImpl<PlayerEvent_MediaControl>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_MediaControl&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode => Object.hash(runtimeType,action);

@override
String toString() {
  return 'PlayerEvent.mediaControl(action: $action)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_MediaControlCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_MediaControlCopyWith(PlayerEvent_MediaControl value, $Res Function(PlayerEvent_MediaControl) _then) = _$PlayerEvent_MediaControlCopyWithImpl;
@useResult
$Res call({
 MediaAction action
});


$MediaActionCopyWith<$Res> get action;

}
/// @nodoc
class _$PlayerEvent_MediaControlCopyWithImpl<$Res>
    implements $PlayerEvent_MediaControlCopyWith<$Res> {
  _$PlayerEvent_MediaControlCopyWithImpl(this._self, this._then);

  final PlayerEvent_MediaControl _self;
  final $Res Function(PlayerEvent_MediaControl) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? action = null,}) {
  return _then(PlayerEvent_MediaControl(
action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as MediaAction,
  ));
}

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MediaActionCopyWith<$Res> get action {
  
  return $MediaActionCopyWith<$Res>(_self.action, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}

/// @nodoc


class PlayerEvent_DeviceChanged extends PlayerEvent {
  const PlayerEvent_DeviceChanged({required this.name, required this.sampleRate}): super._();
  

 final  String name;
 final  int sampleRate;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_DeviceChangedCopyWith<PlayerEvent_DeviceChanged> get copyWith => _$PlayerEvent_DeviceChangedCopyWithImpl<PlayerEvent_DeviceChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_DeviceChanged&&(identical(other.name, name) || other.name == name)&&(identical(other.sampleRate, sampleRate) || other.sampleRate == sampleRate));
}


@override
int get hashCode => Object.hash(runtimeType,name,sampleRate);

@override
String toString() {
  return 'PlayerEvent.deviceChanged(name: $name, sampleRate: $sampleRate)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_DeviceChangedCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_DeviceChangedCopyWith(PlayerEvent_DeviceChanged value, $Res Function(PlayerEvent_DeviceChanged) _then) = _$PlayerEvent_DeviceChangedCopyWithImpl;
@useResult
$Res call({
 String name, int sampleRate
});




}
/// @nodoc
class _$PlayerEvent_DeviceChangedCopyWithImpl<$Res>
    implements $PlayerEvent_DeviceChangedCopyWith<$Res> {
  _$PlayerEvent_DeviceChangedCopyWithImpl(this._self, this._then);

  final PlayerEvent_DeviceChanged _self;
  final $Res Function(PlayerEvent_DeviceChanged) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? sampleRate = null,}) {
  return _then(PlayerEvent_DeviceChanged(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sampleRate: null == sampleRate ? _self.sampleRate : sampleRate // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class PlayerEvent_Error extends PlayerEvent {
  const PlayerEvent_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_ErrorCopyWith<PlayerEvent_Error> get copyWith => _$PlayerEvent_ErrorCopyWithImpl<PlayerEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'PlayerEvent.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_ErrorCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_ErrorCopyWith(PlayerEvent_Error value, $Res Function(PlayerEvent_Error) _then) = _$PlayerEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$PlayerEvent_ErrorCopyWithImpl<$Res>
    implements $PlayerEvent_ErrorCopyWith<$Res> {
  _$PlayerEvent_ErrorCopyWithImpl(this._self, this._then);

  final PlayerEvent_Error _self;
  final $Res Function(PlayerEvent_Error) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(PlayerEvent_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$TransitionMode {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TransitionMode);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TransitionMode()';
}


}

/// @nodoc
class $TransitionModeCopyWith<$Res>  {
$TransitionModeCopyWith(TransitionMode _, $Res Function(TransitionMode) __);
}


/// Adds pattern-matching-related methods to [TransitionMode].
extension TransitionModePatterns on TransitionMode {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TransitionMode_Gapless value)?  gapless,TResult Function( TransitionMode_Crossfade value)?  crossfade,TResult Function( TransitionMode_Cut value)?  cut,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TransitionMode_Gapless() when gapless != null:
return gapless(_that);case TransitionMode_Crossfade() when crossfade != null:
return crossfade(_that);case TransitionMode_Cut() when cut != null:
return cut(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TransitionMode_Gapless value)  gapless,required TResult Function( TransitionMode_Crossfade value)  crossfade,required TResult Function( TransitionMode_Cut value)  cut,}){
final _that = this;
switch (_that) {
case TransitionMode_Gapless():
return gapless(_that);case TransitionMode_Crossfade():
return crossfade(_that);case TransitionMode_Cut():
return cut(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TransitionMode_Gapless value)?  gapless,TResult? Function( TransitionMode_Crossfade value)?  crossfade,TResult? Function( TransitionMode_Cut value)?  cut,}){
final _that = this;
switch (_that) {
case TransitionMode_Gapless() when gapless != null:
return gapless(_that);case TransitionMode_Crossfade() when crossfade != null:
return crossfade(_that);case TransitionMode_Cut() when cut != null:
return cut(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  gapless,TResult Function( int ms)?  crossfade,TResult Function()?  cut,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TransitionMode_Gapless() when gapless != null:
return gapless();case TransitionMode_Crossfade() when crossfade != null:
return crossfade(_that.ms);case TransitionMode_Cut() when cut != null:
return cut();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  gapless,required TResult Function( int ms)  crossfade,required TResult Function()  cut,}) {final _that = this;
switch (_that) {
case TransitionMode_Gapless():
return gapless();case TransitionMode_Crossfade():
return crossfade(_that.ms);case TransitionMode_Cut():
return cut();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  gapless,TResult? Function( int ms)?  crossfade,TResult? Function()?  cut,}) {final _that = this;
switch (_that) {
case TransitionMode_Gapless() when gapless != null:
return gapless();case TransitionMode_Crossfade() when crossfade != null:
return crossfade(_that.ms);case TransitionMode_Cut() when cut != null:
return cut();case _:
  return null;

}
}

}

/// @nodoc


class TransitionMode_Gapless extends TransitionMode {
  const TransitionMode_Gapless(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TransitionMode_Gapless);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TransitionMode.gapless()';
}


}




/// @nodoc


class TransitionMode_Crossfade extends TransitionMode {
  const TransitionMode_Crossfade({required this.ms}): super._();
  

 final  int ms;

/// Create a copy of TransitionMode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransitionMode_CrossfadeCopyWith<TransitionMode_Crossfade> get copyWith => _$TransitionMode_CrossfadeCopyWithImpl<TransitionMode_Crossfade>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TransitionMode_Crossfade&&(identical(other.ms, ms) || other.ms == ms));
}


@override
int get hashCode => Object.hash(runtimeType,ms);

@override
String toString() {
  return 'TransitionMode.crossfade(ms: $ms)';
}


}

/// @nodoc
abstract mixin class $TransitionMode_CrossfadeCopyWith<$Res> implements $TransitionModeCopyWith<$Res> {
  factory $TransitionMode_CrossfadeCopyWith(TransitionMode_Crossfade value, $Res Function(TransitionMode_Crossfade) _then) = _$TransitionMode_CrossfadeCopyWithImpl;
@useResult
$Res call({
 int ms
});




}
/// @nodoc
class _$TransitionMode_CrossfadeCopyWithImpl<$Res>
    implements $TransitionMode_CrossfadeCopyWith<$Res> {
  _$TransitionMode_CrossfadeCopyWithImpl(this._self, this._then);

  final TransitionMode_Crossfade _self;
  final $Res Function(TransitionMode_Crossfade) _then;

/// Create a copy of TransitionMode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ms = null,}) {
  return _then(TransitionMode_Crossfade(
ms: null == ms ? _self.ms : ms // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class TransitionMode_Cut extends TransitionMode {
  const TransitionMode_Cut(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TransitionMode_Cut);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TransitionMode.cut()';
}


}




// dart format on
