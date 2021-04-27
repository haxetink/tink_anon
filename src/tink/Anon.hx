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
        var resultCt = ComplexType.TAnonymous(resultCtFields);
        
        for(f in targetFields) {
          var fname = f.name;
          var optional = f.meta.has(':optional');
          var nested = f.type.reduce().match(TAnonymous(_));
          
          switch patchFields.find(p -> p.field == fname) {
            case null:
              resultCtFields.push({
                name: f.name,
                kind: FVar(f.type.toComplex()),
                #if haxe4
                access: f.isFinal ? [AFinal] : [],
                #end
                pos: f.pos,
              });
            
              if(optional) {
                setters.push(macro if(Reflect.hasField(target, $v{fname})) result.$fname = target.$fname);
              } else {
                setters.push(macro result.$fname = target.$fname);
              }
            case {expr: p = {expr: EObjectDecl(_), pos: pos}}:
              if(nested) {
                
                resultCtFields.push({
                  name: f.name,
                  kind: FVar(Context.typeof(macro tink.Anon.transform($target.$fname, $p)).toComplex()),
                  meta: optional ? [{name: ':optional', pos: f.pos}] : [],
                  #if haxe4
                  access: f.isFinal ? [AFinal] : [],
                  #end
                  pos: f.pos,
                });
              
                if(optional) 
                  setters.push(macro if(Reflect.hasField(target, $v{fname})) result.$fname = tink.Anon.transform(target.$fname, $p));
                else
                  setters.push(macro result.$fname = tink.Anon.transform(target.$fname, $p));
              } else {
                pos.error('Cannot apply object patch to non-nested field. Use a function instead');
              }
            case {expr: p = {expr: EFunction(_)}}:
              
              resultCtFields.push({
                name: f.name,
                kind: FVar(Context.typeof(macro ${p}($target.$fname)).toComplex()),
                meta: optional ? [{name: ':optional', pos: f.pos}] : [],
                #if haxe4
                access: f.isFinal ? [AFinal] : [],
                #end
                pos: f.pos,
              });
              
              if(optional)
                setters.push(macro if(Reflect.hasField(target, $v{fname})) result.$fname = ${p}(target.$fname));
              else
                setters.push(macro result.$fname = ${p}(target.$fname));
            case {expr: p}:
              p.pos.error('This expression is currently not supported');
          }
        }
        
        macro {
          var target = $target;
          var result:Dynamic = {};
          $b{setters};
          (result:$resultCt);
        }
      case _:
        target.pos.error('Expected anonymous object');
    }
  }
}