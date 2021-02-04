package tink.anon;

@:genericBuild(#if haxe4 tink.anon.Partial.build() #else "haxe 4 required" #end)
class Partial<T> {}