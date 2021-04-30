# Tinkerbell Anonymous Object Helpers

There's really just two functions for merging and splatting objects. It is advised to use them through `import tink.Anon.*`.

## Merge

The `tink.Anon.merge` macro takes a variable number of expressions and merges them into one object. There are three kinds of expressions that are treated differently:

- object literals: the macro attempts to merge *all* fields of *all* object literals into one expression. If there is a duplicate field, this will lead to an error, e.g. `tink.Anon.merge({ foo: 12 }, { foo: 13 })` will not compile.
- `ident = expr` which is a shorthand for `{ ident: expr }` which is treated as any object literal
- any other expressions are stored in a temporary variable, and have their fields used in order of appearance. Fields for which there is already a value will be skipped, e.g. `tink.Anon.merge([], 's').length == 0` while `tink.Anon.merge('s', []).length == 1`.

If the macro can determine the expected type (per `Context.getExpectedType`), only fields that are required will be generated. Superfluous fields in object literals will yield compile time errors:

```haxe
var o = { beep: 5, bop: 4 };
var o2:{ foo:Int, bar: Int, beep: Int, bop: Int } = tink.Anon.merge(o, foo = 3, baz = 5);
//{ foo : Int, bop : Int, beep : Int, bar : Int } has no field baz (Suggestion: bar)
```

Note that merging can also be used to build `@:structInit` objects.

You can for example use this macro to create a copy of an object with just a few fields modified:

```haxe
var player = { x: 10, y: 12, hp: 100 };
player = tink.Anon.merge(player, hp = player.hp - 20);
```

The above will make a new player with 80 hit points. Note that the individually defined `hp` simply takes precedence over the one in `player`. But `tink.Anon.merge(player, hp = player.hp - 20, hp = player.hp - 30);` will be rejected because of duplicate `hp`, which is likely to be a mistake.

## Splat

The `tink.Anon.splat` macro takes the fields of its first argument and declares them as variables. An optional second argument can be an **identifier** (which will be used as a prefix) and an optional third argument can be a filter to restrict which fields will be selected. It must either of the following:
- a **string literal** with `*` as wildcards (and is treated case insensitively). May contain `|` for matching different cases.
- a **regex literal**. 
- an **array literal** of filter expressions of which at least one must match.
- a filter preceeded by a `!` for negation

Example:

```haxe
var o = {
  foobar: 1,
  foofoo: 2,
  barbar: 3,
  barfoo: 4,
}
var foobar = "untouched",
    foofoo = "untouched",
    barbar = "untouched",
    barfoo = "untouched";

tink.Anon.splat(o, xyz);
trace(xyzFoobar);//1

tink.Anon.splat(o, "foo*");
trace(foobar);//1
trace(foofoo);//3
trace(barbar);//untouched

tink.Anon.splat(o, xyz, "*foo");
trace(xyzFoofoo);//2
trace(xyzBarfoo);//4

tink.Anon.splat(o, ~/rba/);
trace(barbar);//3
trace(barfoo);//untouched

tink.Anon.splat(o, !~/rba/);//negated
trace(barfoo);//4
```

## Transform

The `tink.Anon.transform` macro takes two expressions:
- the first argument is the "target" object to be transformed, it must be of anon type
- the second argument is the "transformer" object, it must be an object literal

Each field in the transformer object (if exists) should be a transformation function, to be acted against the same-named field in the target object.

If a target field is an anon object, the corresponding transformer field can also be an object literal in additional to a function. This will allow nested transformations.

Example:

```haxe
tink.Anon.transform(
  {a: 1, b: {c: 2}, d: 3},
  {a: v -> v + 1, b: {c: v -> v * v}
);
```

will be transformed into:

```haxe
var o = {a: 1, b: {c: 2}, d: 3}
{
  a: (v -> v + 1)(o.a),
  b: {
    c: (v -> v * v)(o.b.c),
  },
  d: o.d,
}
```

Note that `Reflect.hasField` is used on optional fields, so that non-existent fields will remain non-existent in the result object.


## Macro helpers

At macro time there's an API that helps you use the underlying transformations with more control. Feedback is highly appreciated. Usage is only advised if you have time to deal with breaking changes.
