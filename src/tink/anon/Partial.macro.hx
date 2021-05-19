package tink.anon;

import tink.macro.BuildCache;
import haxe.macro.Type;
import haxe.macro.Expr;
using tink.MacroApi;

class Partial {
  static function get(t:Type):Type
    return switch t.reduce() {
      case TAnonymous(_.get().fields => fields):
        BuildCache.getType('tink.anon.Partial', t, null, ctx -> {
          {
            name: ctx.name,
            kind: TDAlias(TAnonymous([for (f in fields) {
              // #if haxe4
              // access: f.isFinal ? [AFinal] : [],
              // #end
              name: f.name,
              meta: [{ name: ':optional', params: [], pos: (macro null).pos }],
              pos: f.pos,
              kind: switch f.kind {
                case FVar(read, write):
                  FProp(read.accessToName(true), read.accessToName(false), get(f.type).toComplex());
                case FMethod(k):
                  f.pos.error('methods not supported');
              }
            }])),
            pack: [],
            pos: ctx.pos,
            fields: [],
          }
        });
      default: t;
    }

  static function build()
    return get(BuildCache.getParam('tink.anon.Partial').sure());
}