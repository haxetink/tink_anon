package tink.anon;

#if macro
import haxe.macro.Context.*;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.macro.BuildCache;

using StringTools;
using haxe.macro.Tools;
using tink.MacroApi;
using tink.CoreApi;

typedef Part = {
  var name(default, null):String;
  var pos(default, null):Position;
  function getValue(expected:Option<Type>):Expr;
  @:optional var quotes(default, null):QuoteStatus;
}

enum RequireFields {
  RStatic(fields:Map<String, FieldInfo>);
  RDynamic(?type:Type);
}

enum FieldWrite {
  WNever;
  WPrivate;
  WPlain;
}

typedef FieldInfo = {
  var optional(default, null):Bool;
  var write(default, null):FieldWrite;
  var name(default, null):String;
  var type(default, null):Lazy<Option<Type>>;
}

class Macro {

  static public function buildReadOnly() {
    return BuildCache.getType('tink.anon.ReadOnly', function(ctx) {
      var name = ctx.name;
      var ct = ctx.type.toComplex();
      var def = macro class $name {};
      function add(c:TypeDefinition) def.fields = def.fields.concat(c.fields);

      switch ctx.type.reduce() {
        case TAnonymous(_.get() => {fields: fields}):
          for(field in fields) {
            var fname = field.name;
            var ct = field.type.toComplex();
            if(field.type.reduce().match(TAnonymous(_))) ct = macro:tink.anon.ReadOnly<$ct>;
            add(macro class {
              var $fname(default, never):$ct;
            });
          }
        default:
          ctx.pos.error('Only supports anonymous structures');
      }

      def.pack = ['tink', 'anon'];
      def.kind = TDStructure;
      return def;
    });
  }

  static public function mergeExpressions(exprs:Array<Expr>, fields, ?pos, ?as) {
    var complex = [],
        individual:Array<Part> = [];

    function add(name, expr, pos)
      individual.push({ name: name, getValue: function (_) return expr, pos: pos });

    for (e in exprs)
      switch e {
        case macro $name = $v:
          add(name.getIdent().sure(), v, name.pos);

        case { expr: EObjectDecl(fields) }:

          for (f in fields)
            add(f.field, f.expr, f.expr.pos);

        default:
          complex.push(e);
      }

    return mergeParts(individual, complex, fields, null, pos, as);
  }

  static public function mergeParts(
      individual:Array<Part>, complex:Array<Expr>,
      fields:RequireFields, ?resolveAlias:String->String,
      ?pos:Position, ?as:ComplexType, ?errors:{
        function unknownField(name:Part):Outcome<FieldInfo, String>;
        function duplicateField(name:String):String;
        function missingField(field:FieldInfo):String;
      }
    ) {

    pos = pos.sanitize();

    if (errors == null)
      errors = {
        unknownField: function (part) return Failure('unknown field ${part.name}'),
        duplicateField: function (name) return 'duplicate field $name',
        missingField: function (f) return 'missing field ${f.name}',
      }

    inline function resolve(o)
      return
        if (resolveAlias != null) resolveAlias(o.name);
        else o.name;

    var obj:Array<ObjectField> = [],
        vars:Array<Var> = [],
        optionals:Array<Expr> = [],
        defined = new Map(),
        retName = MacroApi.tempName();

    var getField = switch fields {
      case RStatic(fields):
        function (name) return fields.get(name);
      case RDynamic(t):
        var t:Lazy<Option<Type>> = switch t {
          case null: None;
          default: Some(t);
        }
        function (name) return {
          optional: false,
          name: name,
          type: t,
          write: WPlain,
        }
    }

    var ret = EObjectDecl(obj).at(pos);
    if (as != null)
      ret = ret.as(as);

    for (p in individual) {

      var name = resolve(p);

      if (defined[name])
        p.pos.error(errors.duplicateField(name));

      defined[name] = true;

      var info = switch getField(name) {
        case null:
          switch errors.unknownField(p) {
            case Success(v): v;
            case Failure(e): p.pos.error(e);
          }
        case v:
          v;
      }

      var o:ObjectField = { field: info.name, expr: p.getValue(info.type.get()), quotes: p.quotes };
      Reflect.setField(o, 'name_pos', p.pos);
      obj.push(o);
    }

    var include = switch getLocalClass() {
      case null:
        null;
      case _.get() => self:
        function getId(cl:ClassType)
          return cl.module + '.' + cl.name;

        var chain = new Map();
        { // this could probably be cached
          var cur = self;
          while (true) {
            chain[getId(cur)] = true;
            switch cur.superClass {
              case null: break;
              case v: cur = v.t.get();
            }
          }
        }
        function (other:ClassType, f:ClassField) {
          if (f.isPublic) return true;
          if (other.isInterface) return false;
          return chain.exists(getId(other));
        }
    }

    for (o in complex) {
      var ot = typeof(o);
      var given = switch ot.reduce() {
        case t = TInst(_.get() => cl, _):
          classFields(t, include, cl);
        case TAnonymous(a):
          anonFields(a.get());
        default:
          o.reject('type has no fields (${ot.toString()})');
      }

      var varName = null;
      for (found in given) {
        var name = resolve(found);

        if (!defined[name])
          switch getField(name) {
            case null:
            case { optional: optional, type: type, write: write }:
              defined[name] = true;
              if (varName == null) {
                varName = '__o${vars.length}';
                vars.push({
                  name: varName,
                  type: null,
                  expr: o
                });
              }

              var value = {
                var name = found.name;
                macro @:pos(o.pos) $i{varName}.$name;
              }

              switch type.get() {
                case Some(_.toComplex() => t):
                  value = macro @:pos(value.pos) ($value : $t);
                default:
              }

              switch [optional && found.optional, write] {
                case [true, WNever]:
                  optionals.push(macro switch ($value) {
                    case null:
                    case v: untyped $i{retName}.$name = v; //not exactly elegant ... it might be cleverer to purge nulls in a postprocessing step
                  });
                case [true, _]:
                  optionals.push(macro switch ($value) {
                    case null:
                    case v: @:privateAccess $i{retName}.$name = v;
                  });
                default:
                    obj.push({ field: name, expr: value });
              }
          }
      }
    }

    switch fields {
      case RStatic(fields):
        for (f in fields)
          if (!(defined[f.name] || f.optional))
            pos.error(errors.missingField(f));
      default:
    }

    if (optionals.length > 0) {
      optionals.unshift(macro @:pos(pos) var $retName = $ret);
      optionals.push(macro @:pos(pos) $i{retName});
      ret = optionals.toBlock();
    }

    return switch vars {
      case []: ret;
      default:
        EVars(vars).at(pos).concat(ret);
    }
  }

  static public function drillAbstracts(type:Type) {
    function drill(type:haxe.macro.Type):Option<haxe.macro.Type> {
      return
        if(type == null)
          None;
        else switch type.reduce() {
          case t = TAbstract(_.get() => {from: types, params: params}, concrete):
            for(type in types)
              switch drill(haxe.macro.TypeTools.applyTypeParameters(type.t, params, concrete)) {
                case Some(t): return Some(t);
                case _: // try next
              }
            None;
          case t = TAnonymous(_): Some(t);
          case _: None;
        }
    }

    return return drill(type).or(type);
  }

  static function mustSkip(c:ClassField, ?isExtern:Bool)
    return switch c.kind {
      case FMethod(_) if (isExtern): true;
      case FMethod(MethMacro): true;
      case FMethod(MethInline) if (c.meta.has(':extern')): true;
      default: false;
    }

  static function writeAccess(c:ClassField)
    return switch c {
      #if haxe4
      case { isFinal: true }: WNever;
      #end
      case { kind: FMethod(MethDynamic) }: WPlain;
      case { kind: FMethod(_) }: WNever;
      case { kind: FVar(_, AccNever) }: WNever;
      default: WPrivate;
    }

  static function takesAll(a:AbstractType) {

    for (f in a.from)
      switch f.field {
        case null: // do something here?
        case f:
          switch f.type.reduce() {
            case TFun(args, _):
              switch args[0].t {
                case TInst(_.get() => { kind: KTypeParameter([]) }, _):
                  return true;
                default:
              }
            default:
          }
      }

    return false;
  }

  static public function requiredFields(type:Type, ?pos:Position):RequireFields
    return
      if (type == null) RDynamic();
      else switch type.reduce() {
        case TDynamic(t): RDynamic(t);
        case TMono(_.get() => null): RDynamic();
        case TAnonymous(a):
          RStatic(anonFields(a.get()));
        case TInst(_.get() => cl, _) if (!cl.isInterface && cl.meta.has(':structInit')):
          RStatic(classFields(type, function (cl, f) return f.isPublic && f.kind.match(FVar(_)), cl));
        case TAbstract(_.get() => a, [t]) if (takesAll(a)):
          requiredFields(t);
        default:
          pos.error('expected type should be struct or @:structInit but found ${type.toString()}');
      }

  static public function fieldsToInfos(fields:Iterable<ClassField>, ?getType:ClassField->Type)
    return [for (f in fields)
      f.name => ({
        name: f.name,
        optional: f.meta.has(':optional'),
        type: switch getType {
          case null: Some(f.type);
          default: function() return Some(getType(f));
        },
        write: writeAccess(f),
      }:FieldInfo)
    ];

  static function anonFields(a:AnonType)
    return fieldsToInfos(a.fields);

  static function classFields(type:Type, include:ClassType->ClassField->Bool, ?cl:ClassType) {
    if (cl == null)
      cl = switch type {
        case TInst(_.get() => cl, _): cl;
        default: throw 'assert';
      }

    var ret = new Map(),
        sample = Lazy.ofFunc(function () {
          var ct = type.toComplex();
          return macro (cast null : $ct);
        });

    function crawl(cl:ClassType) {
      for (f in cl.fields.get()) if (include(cl, f) && !mustSkip(f, cl.isExtern))
        ret[f.name] = ({
          name: f.name,
          optional: f.meta.has(':optional'),
          type: function () return Some(typeof(sample.get().field(f.name))),
          write: writeAccess(f),
        }:FieldInfo);
      switch cl.superClass {
        case null:
        case v: crawl(v.t.get());
      }
    }

    crawl(cl);
    return ret;
  }

  static function parseFilter(e:Expr)
    return switch e {
      case null | macro null:
        function (_) return true;
      case macro !$e:
        var f = parseFilter(e);
        function (x) return !f(x);
      case { expr: EArrayDecl(_.map(parseFilter) => filters) }:
        return function (s) {
          for (f in filters) if (f(s)) return true;
          return false;
        }
      case macro $i{ident}:
        return function (s) return s == ident;
      case { expr: EConst(CString(s)) }:
        s = s.replace('*', '.*');
        new EReg('^($s)$', 'i').match;
      case { expr: EConst(CRegexp(pat, flags)) }:
        new EReg(pat, flags).match;
      default:
        e.reject('Not a valid filter. Must be a string constant or a regex literal');
    }

  static public function makeSplat(e:Expr, ?prefix:Expr, ?filter:Expr) {

    var include = null;
    var prefix = switch prefix.getIdent() {
      case Success('null') | Failure(_):
        include = parseFilter(prefix);
        null;
      case Success(v):
        include = parseFilter(filter);
        v;
    }

    function getName(name:String)
      return
        if (prefix == null) name;
        else prefix + name.charAt(0).toUpperCase() + name.substr(1);

    var vars = [],
        owner = MacroApi.tempName();

    var ret = EVars(vars).at(e.pos);

    vars.push({
      name: owner,
      expr: e,
      type: null,
    });

    for (f in e.typeof().sure().getFields().sure())
      if (f.isPublic && !mustSkip(f) && include(f.name)) {//TODO: pass isExtern
        var field = f.name;
        vars.push({
          name: getName(f.name),
          expr: macro @:pos(e.pos) $i{owner}.$field,
          type: null,
        });
      }

    return ret;
  }

}
#end