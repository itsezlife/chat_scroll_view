// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_search_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatSearchState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatSearchState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ChatSearchState()';
}


}

/// @nodoc
class $ChatSearchStateCopyWith<$Res>  {
$ChatSearchStateCopyWith(ChatSearchState _, $Res Function(ChatSearchState) __);
}


/// Adds pattern-matching-related methods to [ChatSearchState].
extension ChatSearchStatePatterns on ChatSearchState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _ChatSearchClosed value)?  closed,TResult Function( _ChatSearchIdle value)?  idle,TResult Function( _ChatSearchSearching value)?  searching,TResult Function( _ChatSearchPopulated value)?  populated,TResult Function( _ChatSearchEmpty value)?  empty,TResult Function( _ChatSearchFailure value)?  failure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatSearchClosed() when closed != null:
return closed(_that);case _ChatSearchIdle() when idle != null:
return idle(_that);case _ChatSearchSearching() when searching != null:
return searching(_that);case _ChatSearchPopulated() when populated != null:
return populated(_that);case _ChatSearchEmpty() when empty != null:
return empty(_that);case _ChatSearchFailure() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _ChatSearchClosed value)  closed,required TResult Function( _ChatSearchIdle value)  idle,required TResult Function( _ChatSearchSearching value)  searching,required TResult Function( _ChatSearchPopulated value)  populated,required TResult Function( _ChatSearchEmpty value)  empty,required TResult Function( _ChatSearchFailure value)  failure,}){
final _that = this;
switch (_that) {
case _ChatSearchClosed():
return closed(_that);case _ChatSearchIdle():
return idle(_that);case _ChatSearchSearching():
return searching(_that);case _ChatSearchPopulated():
return populated(_that);case _ChatSearchEmpty():
return empty(_that);case _ChatSearchFailure():
return failure(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _ChatSearchClosed value)?  closed,TResult? Function( _ChatSearchIdle value)?  idle,TResult? Function( _ChatSearchSearching value)?  searching,TResult? Function( _ChatSearchPopulated value)?  populated,TResult? Function( _ChatSearchEmpty value)?  empty,TResult? Function( _ChatSearchFailure value)?  failure,}){
final _that = this;
switch (_that) {
case _ChatSearchClosed() when closed != null:
return closed(_that);case _ChatSearchIdle() when idle != null:
return idle(_that);case _ChatSearchSearching() when searching != null:
return searching(_that);case _ChatSearchPopulated() when populated != null:
return populated(_that);case _ChatSearchEmpty() when empty != null:
return empty(_that);case _ChatSearchFailure() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  closed,TResult Function()?  idle,TResult Function( String query)?  searching,TResult Function( String query,  List<int> hits,  int index)?  populated,TResult Function( String query)?  empty,TResult Function( String query,  Object error)?  failure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatSearchClosed() when closed != null:
return closed();case _ChatSearchIdle() when idle != null:
return idle();case _ChatSearchSearching() when searching != null:
return searching(_that.query);case _ChatSearchPopulated() when populated != null:
return populated(_that.query,_that.hits,_that.index);case _ChatSearchEmpty() when empty != null:
return empty(_that.query);case _ChatSearchFailure() when failure != null:
return failure(_that.query,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  closed,required TResult Function()  idle,required TResult Function( String query)  searching,required TResult Function( String query,  List<int> hits,  int index)  populated,required TResult Function( String query)  empty,required TResult Function( String query,  Object error)  failure,}) {final _that = this;
switch (_that) {
case _ChatSearchClosed():
return closed();case _ChatSearchIdle():
return idle();case _ChatSearchSearching():
return searching(_that.query);case _ChatSearchPopulated():
return populated(_that.query,_that.hits,_that.index);case _ChatSearchEmpty():
return empty(_that.query);case _ChatSearchFailure():
return failure(_that.query,_that.error);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  closed,TResult? Function()?  idle,TResult? Function( String query)?  searching,TResult? Function( String query,  List<int> hits,  int index)?  populated,TResult? Function( String query)?  empty,TResult? Function( String query,  Object error)?  failure,}) {final _that = this;
switch (_that) {
case _ChatSearchClosed() when closed != null:
return closed();case _ChatSearchIdle() when idle != null:
return idle();case _ChatSearchSearching() when searching != null:
return searching(_that.query);case _ChatSearchPopulated() when populated != null:
return populated(_that.query,_that.hits,_that.index);case _ChatSearchEmpty() when empty != null:
return empty(_that.query);case _ChatSearchFailure() when failure != null:
return failure(_that.query,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ChatSearchClosed implements ChatSearchState {
  const _ChatSearchClosed();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatSearchClosed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ChatSearchState.closed()';
}


}




/// @nodoc


class _ChatSearchIdle implements ChatSearchState {
  const _ChatSearchIdle();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatSearchIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ChatSearchState.idle()';
}


}




/// @nodoc


class _ChatSearchSearching implements ChatSearchState {
  const _ChatSearchSearching({required this.query});
  

 final  String query;

/// Create a copy of ChatSearchState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatSearchSearchingCopyWith<_ChatSearchSearching> get copyWith => __$ChatSearchSearchingCopyWithImpl<_ChatSearchSearching>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatSearchSearching&&(identical(other.query, query) || other.query == query));
}


@override
int get hashCode => Object.hash(runtimeType,query);

@override
String toString() {
  return 'ChatSearchState.searching(query: $query)';
}


}

/// @nodoc
abstract mixin class _$ChatSearchSearchingCopyWith<$Res> implements $ChatSearchStateCopyWith<$Res> {
  factory _$ChatSearchSearchingCopyWith(_ChatSearchSearching value, $Res Function(_ChatSearchSearching) _then) = __$ChatSearchSearchingCopyWithImpl;
@useResult
$Res call({
 String query
});




}
/// @nodoc
class __$ChatSearchSearchingCopyWithImpl<$Res>
    implements _$ChatSearchSearchingCopyWith<$Res> {
  __$ChatSearchSearchingCopyWithImpl(this._self, this._then);

  final _ChatSearchSearching _self;
  final $Res Function(_ChatSearchSearching) _then;

/// Create a copy of ChatSearchState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,}) {
  return _then(_ChatSearchSearching(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class _ChatSearchPopulated implements ChatSearchState {
  const _ChatSearchPopulated({required this.query, required final  List<int> hits, required this.index}): _hits = hits;
  

 final  String query;
 final  List<int> _hits;
 List<int> get hits {
  if (_hits is EqualUnmodifiableListView) return _hits;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_hits);
}

 final  int index;

/// Create a copy of ChatSearchState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatSearchPopulatedCopyWith<_ChatSearchPopulated> get copyWith => __$ChatSearchPopulatedCopyWithImpl<_ChatSearchPopulated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatSearchPopulated&&(identical(other.query, query) || other.query == query)&&const DeepCollectionEquality().equals(other._hits, _hits)&&(identical(other.index, index) || other.index == index));
}


@override
int get hashCode => Object.hash(runtimeType,query,const DeepCollectionEquality().hash(_hits),index);

@override
String toString() {
  return 'ChatSearchState.populated(query: $query, hits: $hits, index: $index)';
}


}

/// @nodoc
abstract mixin class _$ChatSearchPopulatedCopyWith<$Res> implements $ChatSearchStateCopyWith<$Res> {
  factory _$ChatSearchPopulatedCopyWith(_ChatSearchPopulated value, $Res Function(_ChatSearchPopulated) _then) = __$ChatSearchPopulatedCopyWithImpl;
@useResult
$Res call({
 String query, List<int> hits, int index
});




}
/// @nodoc
class __$ChatSearchPopulatedCopyWithImpl<$Res>
    implements _$ChatSearchPopulatedCopyWith<$Res> {
  __$ChatSearchPopulatedCopyWithImpl(this._self, this._then);

  final _ChatSearchPopulated _self;
  final $Res Function(_ChatSearchPopulated) _then;

/// Create a copy of ChatSearchState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,Object? hits = null,Object? index = null,}) {
  return _then(_ChatSearchPopulated(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,hits: null == hits ? _self._hits : hits // ignore: cast_nullable_to_non_nullable
as List<int>,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class _ChatSearchEmpty implements ChatSearchState {
  const _ChatSearchEmpty({required this.query});
  

 final  String query;

/// Create a copy of ChatSearchState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatSearchEmptyCopyWith<_ChatSearchEmpty> get copyWith => __$ChatSearchEmptyCopyWithImpl<_ChatSearchEmpty>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatSearchEmpty&&(identical(other.query, query) || other.query == query));
}


@override
int get hashCode => Object.hash(runtimeType,query);

@override
String toString() {
  return 'ChatSearchState.empty(query: $query)';
}


}

/// @nodoc
abstract mixin class _$ChatSearchEmptyCopyWith<$Res> implements $ChatSearchStateCopyWith<$Res> {
  factory _$ChatSearchEmptyCopyWith(_ChatSearchEmpty value, $Res Function(_ChatSearchEmpty) _then) = __$ChatSearchEmptyCopyWithImpl;
@useResult
$Res call({
 String query
});




}
/// @nodoc
class __$ChatSearchEmptyCopyWithImpl<$Res>
    implements _$ChatSearchEmptyCopyWith<$Res> {
  __$ChatSearchEmptyCopyWithImpl(this._self, this._then);

  final _ChatSearchEmpty _self;
  final $Res Function(_ChatSearchEmpty) _then;

/// Create a copy of ChatSearchState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,}) {
  return _then(_ChatSearchEmpty(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class _ChatSearchFailure implements ChatSearchState {
  const _ChatSearchFailure({required this.query, required this.error});
  

 final  String query;
 final  Object error;

/// Create a copy of ChatSearchState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatSearchFailureCopyWith<_ChatSearchFailure> get copyWith => __$ChatSearchFailureCopyWithImpl<_ChatSearchFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatSearchFailure&&(identical(other.query, query) || other.query == query)&&const DeepCollectionEquality().equals(other.error, error));
}


@override
int get hashCode => Object.hash(runtimeType,query,const DeepCollectionEquality().hash(error));

@override
String toString() {
  return 'ChatSearchState.failure(query: $query, error: $error)';
}


}

/// @nodoc
abstract mixin class _$ChatSearchFailureCopyWith<$Res> implements $ChatSearchStateCopyWith<$Res> {
  factory _$ChatSearchFailureCopyWith(_ChatSearchFailure value, $Res Function(_ChatSearchFailure) _then) = __$ChatSearchFailureCopyWithImpl;
@useResult
$Res call({
 String query, Object error
});




}
/// @nodoc
class __$ChatSearchFailureCopyWithImpl<$Res>
    implements _$ChatSearchFailureCopyWith<$Res> {
  __$ChatSearchFailureCopyWithImpl(this._self, this._then);

  final _ChatSearchFailure _self;
  final $Res Function(_ChatSearchFailure) _then;

/// Create a copy of ChatSearchState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,Object? error = null,}) {
  return _then(_ChatSearchFailure(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error ,
  ));
}


}

// dart format on
