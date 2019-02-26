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
    
    function getType(type:haxe.macro.Type):haxe.macro.Type {
      var ret =  switch type {
        case TType(_): getType(type.reduce(true));
        case TAbstract(_.get() => {name: 'Null', pack: []}, [t1]): getType(t1);
        case TLazy(f): getType(f());
        case TAbstract(_.get() => {name: 'EitherType', pack: ['haxe', 'extern']}, [t1, t2]):
          switch [getType(t1), getType(t2)] {
            case [t = TAnonymous(_), TAnonymous(_)]: t; // TODO: choosing the first type for now, should try both though
            case [t = TAnonymous(_), _]: t;
            case [_, t = TAnonymous(_)]: t;
            case [_, _]: type; // TODO: maybe throw something meaningful?
          }
        case _: type;
      }
      return ret;
    }
    
    var type = getType(Context.getExpectedType());
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