using concurrent

** A wrapper around [Actor.locals]`concurrent::Actor.locals` ensuring a unique namespace per 
** instance. this means you don't have to worry about name clashes. 
** 
** Example usage:
** 
** pre>
**   stash1 := LocalStash()
**   stash1["wot"] = "ever"
** 
**   stash2 := LocalStash()
**   stash2["wot"] = "banana"
** 
**   Obj.echo(stash1["wot"])  // --> ever
** <pre
** 
** Though typically you would create calculated field wrappers:
** 
** pre>
** const class Example
**   private const LocalStash stash := LocalStash(typeof)
**   
**   MyService wotever {
**     get { stash["wotever"] }
**     set { stash["wotever"] = it }
**   }
** }
** <pre
**  
const class LocalStash {
	private const Str prefix
	
	private Int? counter {
		get { Actor.locals["${typeof.qname}.counter"] }
		set { Actor.locals["${typeof.qname}.counter"] = it }
	}

	new make() {
		this.prefix = createPrefix(typeof)
	}

	** Adds the type name to the 'locals' key - handy for debugging.
	** See `IocHelper.locals`
	new makeFromType(Type type) {
		this.prefix = createPrefix(type)
	}
	
	** Get the value for the specified name.
	@Operator
	Obj? get(Str name, |->Obj|? defFunc := null) {
		val := Actor.locals[key(name)]
		if (val == null) {
			if (defFunc != null) {
				val = defFunc.call
				set(name, val)
			}
		}
		return val
	}

	** Set the value for the specified name. If the name was already mapped, this overwrites the old 
	** value.
	@Operator
	Void set(Str name, Obj? value) {
		Actor.locals[key(name)] = value
	}
	
	** Returns all keys associated / used with this stash 
	Str[] keys() {
		Actor.locals.keys
			.findAll { it.startsWith(prefix) }
			.map |key->Str| { stripPrefix(key) }
	}

	** Remove the name/value pair from the stash and returns the value that was. If the key was not 
	** mapped then return null.
	** 
	** @since 1.3.0
	Obj? remove(Str name) {
		Actor.locals.remove(key(name))
	}
	
	** Removes all key/value pairs from this stash
	** 
	** @since 1.3.0
	Void clear() {
		keys.each { Actor.locals.remove(it) }
	}
	
	override Str toStr() {
		"LocalStash with prefix - $prefix"
	}
	
	private Str createPrefix(Type type) {
		count 	:= counter ?: 1
		padded	:= count.toStr.padl(4, '0')
		prefix 	:= "${type.name}.${padded}."
		counter = count + 1
		return prefix
	}
	
	private Str key(Str name) {
		return "${prefix}${name}"
	}
	
	private Str stripPrefix(Str name) {
		if (name.startsWith(prefix))
			return name[prefix.size..-1]
		else
			return name
	}	
}