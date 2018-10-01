package tink;

#if macro
import haxe.macro.Context;
import tink.anon.Macro.*;
import haxe.macro.Expr;

using tink.MacroApi;
#end

class Anon {
  
  static function getExistentFields(o:{}):{} {
    var ret = {};
    for (f in Reflect.fields(o)) Reflect.setField(ret, f, true);
    return ret;
  }

  macro static public function existentFields(e:Expr) {
    var t = TAnonymous([
      for (f in e.typeof().sure().getFields().sure()) 
        if (f.isPublic && f.meta.has(':optional')) {
          name: f.name,
          kind: FProp('default', 'never', macro : Bool),
          pos: f.pos,
        } 
    ]);
    return macro @:pos(e.pos) @:privateAccess (cast tink.Anon.getExistentFields($e):$t);
  }
  
  macro static public function merge(exprs:Array<Expr>) {
    var type = Context.getExpectedType();
    var ct = type.toComplex();
    return
      mergeExpressions(
        exprs, 
        requiredFields(type),
        ct
      );
  }

  macro static public function splat(e:Expr, ?prefix:Expr, ?filter:Expr) 
    return makeSplat(e, prefix, filter);

}