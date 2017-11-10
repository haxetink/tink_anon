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

  public static macro function cascade<T>(exprs : Array<ExprOf<T>>) : Expr {
    var type = Context.getExpectedType();
    var ct = type.toComplex();
    return
      mergeExpressions(
        exprs,
        requiredFields(type),
        ct,
        true
      );
  }

  macro static public function splat(e:Expr, ?prefix:Expr, ?filter:Expr)
    return makeSplat(e, prefix, filter);

}
