package ;

import haxe.unit.*;
import tink.anon.*;
import tink.Anon.*;
import haxe.extern.EitherType;

class RunTests extends TestCase {

  function testSplat() {
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
    {
      tink.Anon.splat(o, xyz);
      assertEquals(xyzFoobar, 1);

      tink.Anon.splat(o, "foo*");
      assertEquals(foobar, 1);
      assertEquals(foofoo, 2);
      assertEquals(barbar, "untouched");

      tink.Anon.splat(o, xyz, "*foo");
      assertEquals(xyzFoofoo, 2);
      assertEquals(xyzBarfoo, 4);

      tink.Anon.splat(o, ~/rba/);
      assertEquals(barbar, 3);
      assertEquals(barfoo, "untouched");

      tink.Anon.splat(o, !~/rba/);//negated
      assertEquals(barfoo, 4);
    }
    {
      tink.Anon.splat(o, "foo*|*bar");
      assertEquals(foobar, 1);
      assertEquals(foofoo, 2);
      assertEquals(barbar, 3);
      assertEquals(barfoo, "untouched");
    }
    {
      tink.Anon.splat(o, [foobar, barfoo]);
      assertEquals(foobar, 1);
      assertEquals(foofoo, "untouched");
      assertEquals(barbar, "untouched");
      assertEquals(barfoo, 4);
    }
  }
  static function sorted<A>(a:Array<A>) {
    a.sort(Reflect.compare);
    return a;
  }

  function assertFields(expected:String, o:{}, ?pos:haxe.PosInfos) {
    assertEquals(
      sorted(expected.split(',')).join(','),
      sorted(Reflect.fields(o)).join(',')
    );
  }

  function testOptional() {
    var o:{ ?optional: Int } = {};
    o = merge(o);
    assertFalse(Reflect.hasField(o, 'optional'));
  }

  function testMerge() {
    assertEquals(1, merge([1], 'foo').length);
    assertEquals(3, merge('foo', [1]).length);
    var o = {
      foo: 123,
      bar: 'bar',
      blargh: [1,2,3]
    };

    var o2 = merge(o, foo = 12);
    assertEquals(12, o2.foo);
    assertFields('bar,blargh,foo', o2);

    var o3:{ foo: Int, bar:String } = merge(o);
    assertFields('bar,foo', o3);
    //o3 = merge({ bar: Int, foop: 12 }); uncomment to check if compiler gives right suggestion

    var o = merge(x = 1, new FooBar());
    assertEquals('bar', o.bar());
    assertEquals('foo', o.foo());
  }

  function testStructInit() {
    var o = { beep: 5, bop: 4, foo: 2 };
    var o2:Example = tink.Anon.merge(o, foo = 3, bar = 5);
    assertEquals(3, o2.foo);
  }

  function testEitherType() {
    var o:EitherType<{i:Int}, Array<{i:Int}>> = tink.Anon.merge(i = 1);
    assertFalse(Std.is(o, Array));
    assertEquals(1, (cast o).i);

    var o:EitherType<EitherType<Array<{f:Float}>, {i:Int}>, Array<{i:Int}>> = tink.Anon.merge(i = 1);
    assertFalse(Std.is(o, Array));
    assertEquals(1, (cast o).i);
  }

  function testReadOnly() {
    var o:ReadOnly<{i:Int}> = {i: 1};
    assertEquals(1, o.i);
    Should.notCompile(o.i = 3, ~/Cannot access field or identifier i for writing/);
  }

  static function main() {
    var r = new TestRunner();

    r.add(new RunTests());

    travix.Logger.exit(
      if (r.run()) 0
      else 500
    );
  }

}

@:structInit class Example {
  public var foo:Int;
  public var bar:Int;
  public var beep:Int;
  public var bop:Int;
}

class FooBar {
  public function new() {}
  public function foo() return 'foo';
  public function bar() return 'bar';
}