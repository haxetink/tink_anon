package ;

import haxe.unit.*;
import tink.anon.*;
import tink.Anon.*;
import haxe.extern.EitherType;

using tink.CoreApi;

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

  #if haxe4
  function testPartial() {
    var a:Array<Partial<{i:Int,foo:{bar:String}}>> = [
      {},
      {i: 123},
      {foo: {}},
      {foo: { bar: '123' }},
    ];
    assertTrue(true);
  }
  #end

  function testIssue15() {
    function lazy<X>(l:tink.core.Lazy<X>)
      return l.get();

    function future<X>(f:Future<X>) {
      var ret = None;
      f.handle(function (v) ret = Some(v));
      return ret.force();
    }

    function promise<X>(p:Promise<X>)
      return future(p).sure();

    var a = { a: 12 },
        b = { b: 13 };

    var ab = lazy(tink.Anon.merge(a, b));

    assertEquals(12, ab.a);
    assertEquals(13, ab.b);

    var ab = future(tink.Anon.merge(a, b));

    assertEquals(12, ab.a);
    assertEquals(13, ab.b);

    var ab = promise(Promise.lift(true).next(function (_) return tink.Anon.merge(a, b)));

    assertEquals(12, ab.a);
    assertEquals(13, ab.b);

  }
  
  function testTransform() {
    var o:{a:Int, ?b:Int, c:{e:Int, ?f:Int}, ?d:{g:Int, ?h:Int}} = {a: 1, c: {e: 2}}
    var t = transform(o, {
      a: v -> v + 1,
      b: v -> v + 1,
      c: {
        e: v -> v + 1,
        f: v -> v + 1,
      },
      d: {
        g: v -> v + 1,
        h: v -> v + 1,
      }
    });
    assertEquals(2, t.a);
    assertEquals(3, t.c.e);
    assertFalse(Reflect.hasField(t, 'b'));
    assertFalse(Reflect.hasField(t, 'd'));
    assertFalse(Reflect.hasField(t.c, 'f'));
    
    var o:{a:Int, ?b:Int, c:{e:Int, ?f:Int}, ?d:{g:Int, ?h:Int}} = {a: 1, b: 2, c: {e: 3, f: 4}, d: {g: 5, h: 6}}
    var t = transform(o, {
      a: v -> v + 1,
      b: v -> v + 1,
      c: {
        e: v -> v + 1,
        f: v -> v + 1,
      },
      d: {
        g: v -> v + 1,
        h: v -> v * v,
      }
    });
    assertEquals(2, t.a);
    assertEquals(3, t.b);
    assertEquals(4, t.c.e);
    assertEquals(5, t.c.f);
    assertEquals(6, t.d.g);
    assertEquals(36, t.d.h);
    
    var o:{a:Int, ?b:Int, c:{e:Int, ?f:Int}, ?d:{g:Int, ?h:Int}} = {a: 1, c: {e: 3, f: 4}}
    var t = transform(o, {c: v -> v.e});
    assertEquals(1, t.a);
    assertEquals(3, t.c);
    
    #if haxe4
    var o:{final a:Int; final ?b:Int; final c:{e:Int, ?f:Int}; final ?d:{g:Int, ?h:Int};} = {a: 1, c: {e: 3, f: 4}}
    var t = transform(o, {c: v -> v.e});
    assertEquals(1, t.a);
    assertEquals(3, t.c);
    // t.a = 1; // can't write to final
    #end
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

#if haxe4
typedef IIter = Interface<Iterator<Int> & { final foo:Int; }>;
class Iter implements IIter {
  public final foo:Int = 123;
  public function new() {

  }
  public function hasNext()
    return false;
  public function next()
    return foo;
}
#end