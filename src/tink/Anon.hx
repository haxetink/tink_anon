package tink;

#if macro
import haxe.macro.Context;
import tink.anon.Macro.*;
import haxe.macro.Expr;

using tink.MacroApi;
using tink.CoreApi;
using Lambda;
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

    var expected = Context.getExpectedType();
    var type = drillAbstracts(expected);
    var ct = type.toComplex();
    return mergeExpressions(
      exprs,
      requiredFields(type),
      ct
    ).as(expected.toComplex());
  }

  macro static public function splat(e:Expr, ?prefix:Expr, ?filter:Expr)
    return makeSplat(e, prefix, filter);

  
  
  macro static public function transform(target:Expr, patch:Expr) {
    return switch [Context.typeof(target).reduce(), patch.expr] {
      case [TAnonymous(_.get() => {fields: targetFields}), EObjectDecl(patchFields)]:
        var pos = Context.currentPos();
        var setters = [];
        var resultCtFields = [];
        var expected = Context.getExpectedType();
        var expectedFields = switch expected {
          case null: [];
          case _.reduce() => TAnonymous(_.get() => {fields: fields}): fields;
          case _: [];
        }
        
        var resultCt = expected == null ? ComplexType.TAnonymous(resultCtFields) : expected.toComplex();
        
        for(f in targetFields) {
          var fname = f.name;
          var optional = f.meta.has(':optional');
          var nested = f.type.reduce().match(TAnonymous(_));
          
          var expected = switch expectedFields.find(e -> e.name == fname) {
            case null: f.pos.makeBlankType();
            case f: f.type.toComplex();
          }
          
          function addSetter(e) {
            if(optional) {
              setters.push(macro if(Reflect.hasField(target, $v{fname})) (cast result).$fname = $e);
            } else {
              setters.push(macro (cast result).$fname = $e);
            }
          }
          
          function addCtField(ct) {
            resultCtFields.push({
              name: f.name,
              kind: FVar(ct),
              meta: optional ? [{name: ':optional', pos: f.pos}] : [],
              #if haxe4
              access: f.isFinal ? [AFinal] : [],
              #end
              pos: f.pos,
            });
          }
          
          switch patchFields.find(p -> p.field == fname) {
            case null:
              addCtField(f.type.toComplex());
              addSetter(macro target.$fname);
              
            case {expr: p = {pos: pos, expr: EObjectDecl(_)}}:
              if(nested) {
                addCtField(Context.typeof(macro @:pos(pos) (tink.Anon.transform($target.$fname, $p):$expected)).toComplex());
                addSetter(macro @:pos(pos) (tink.Anon.transform(target.$fname, $p):$expected));
              } else {
                pos.error('Cannot apply object patch to non-nested field. Use a function instead');
              }
              
            case {expr: p = {pos: pos, expr: EFunction(_, func = {args: [arg]})}}:
              if(arg.type == null) arg.type = f.type.toComplex();
              if(func.ret == null) func.ret = expected;
              addCtField(Context.typeof(macro @:pos(pos) ${p}($target.$fname)).toComplex());
              addSetter(macro @:pos(pos) ${p}(target.$fname));
              
            case {expr: p}:
              p.pos.error('This expression is currently not supported');
          }
        }
        
        macro @:pos(pos) {
          var target = $target;
          var result:$resultCt = cast {};
          $b{setters};
          result;
        }
      case _:
        target.pos.error('Expected anonymous object');
    }
  }
}