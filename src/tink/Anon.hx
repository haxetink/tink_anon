package tink;

#if macro
import haxe.macro.Context;
import tink.anon.Macro.*;
import haxe.macro.Expr;

using tink.MacroApi;
#end

class Anon {
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
    
  macro static public function replace(exprs:Array<Expr>) 
    return makeReplace(exprs[0], exprs.slice(1));

}