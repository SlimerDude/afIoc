using concurrent::AtomicBool

** (Service) -
** Creates and manages service instances, and performs dependency injection.
** Scopes may also create child scopes.
** 
** Scopes may be dependency injected. 
** Use standard injection to receive the Scope used to create the class instance.
** 
**   syntax: fantom
**   @Inject
**   private Scope scope
** 
** Or to always receive the current active Scope, use a Lazy Func.
**  
**   syntax: fantom
**   @Inject
**   private |->Scope| scope
** 
@Js
const mixin Scope {

	** Returns the unique 'id' of this Scope. 
	abstract Str 		id()
	
	** Returns the parent scope.
	abstract Scope?		parent()
	
	** Returns the registry instance this scope belongs to.
	abstract Registry	registry()
	
	** Returns 'true' if this scope is threaded and may hold non-const services.
	abstract Bool isThreaded()
	
	** Autobuilds an instance of the given type. Autobuilding performs the following:
	** 
	**  - creates an instance via the ctor marked with '@Inject' or the *best* fitting ctor with the most parameters
	**  - inject dependencies into fields (of all visibilities)
	**  - calls any method on the class annotated with '@PostInjection'
	** 
	** 'ctorArgs' (if provided) will be passed as arguments to the constructor.
	** Constructor parameters should be defined in the following order:
	** 
	**   new make(<config>, <ctorArgs>, <dependencies>, <it-block>) { ... }
	** 
	** Note that 'fieldVals' are set by an it-block function, should the ctor define one.
	abstract Obj? build(Type type, Obj?[]? ctorArgs := null, [Field:Obj?]? fieldVals := null)
	
	** Injects services and dependencies into fields of all visibilities and
	** calls any method on the class annotated with '@PostInjection'.
	** 
	** Returns the object passed in for method chaining.
	abstract Obj inject(Obj obj)
	
	** Calls the given method. Any method arguments not given are resolved as dependencies. 
	** 'instance' may be 'null' if calling a static method.
	** Method parameters should be defined in the following order:
	** 
	** 
	**   Void myMethod(<args>, <dependencies>, <default params>) { ... }
	** 
	** Note that nullable and default parameters are treated as optional dependencies.
	** 
	** Returns the result of calling the method.
	abstract Obj? callMethod(Method method, Obj? instance, Obj?[]? args := null)

	** Calls the given func. Any func arguments not given are resolved as dependencies. 
	** Func parameters should be defined in the following order:
	** 
	**   |<args>, <dependencies>, <default params>| { ... }
	** 
	** Note that nullable and default parameters are treated as optional dependencies.
	** 
	** Returns the result of calling the func.
	abstract Obj? callFunc(Func func, Obj?[]? args := null)

	** Resolves a service by its ID. Throws 'IocErr' if the service is not found, unless 'checked' is 'false'.
	abstract Obj? serviceById(Str serviceId, Bool checked := true)

	** Resolves a service by its Type. Throws 'IocErr' if the service is not found, unless 'checked' is 'false'.
	abstract Obj? serviceByType(Type serviceType, Bool checked := true)
	
	** Creates a nested child scope and makes it available to the given function,
	** which is called straight away.
	** The child scope also becomes the *active* scope for the duration of the function.
	** 
	** pre>
	** syntax: fantom
	** scope.createChild("childScopeId") |Scope childScope| {
	**     ...
	** }
	** <pre
	** 
	** When a function is passed in then 'null' is returned because the scope would not be valid 
	** outside of the function.
	** 
	** Advanced users may create *non-active* scopes by **not** passing in a function and
	** using the returned scope. Non-active scopes must be manually destroyed.
	** 
	** pre>
	** syntax: fantom
	** myScope := scope.createChild("myScope")
	** 
	** ... use myScope ...
	** 
	** myScope.destroy
	** <pre
	** 
	** To create an active scope that remains active outside of the closure, use [jailBreak()]`jailBreak`. 
	abstract Scope? createChild(Str scopeId, |Scope|? f := null)

	** *(Advanced Use Only)*
	** 
	** Jail breaks an active scope so it remains *active* outside its closure. 
	** Jail broken scopes are not destroyed so you are responsible for calling 'destroy()' yourself.
	** 
	** pre>
	** syntax: fantom
	** childScope := (Scope?) null
	** 
	** scope.createChild("childScopeId") |childScopeInClosure| {
	**     childScope = childScopeInClosure.jailbreak
	** }
	** 
	** // --> "childScopeId" is still active!
	** echo(scope.registry.activeScope)
	** 
	** ... use childScope here ...
	** childScope.serviceByType(...)
	** 
	** childScope.destroy
	** <pre
	** 
	** Note that jail broken scopes are only active in the current thread, but will remain the active 
	** scope even if the thread is re-entered. 
	abstract This jailBreak()
	
	** *(Advanced Use Only)*
	** 
	** Destroys this scope and releases references to any services created. Calls any scope destroy hooks. 
	** Pops this scope off the active stack.
	** 
	** 'destroy()' does nothing if called more than once.
	abstract Void destroy()
	
	** *(Advanced Use Only)*
	** 
	** Runs the given function with this 'Scope' as the active one. Note this method does *not* destroy the scope. 
	** 
	** Under normal usage, consider using 'createChild(...)' instead.
	abstract Void asActive(|Scope| f)

	** Returns 'true' if this 'Scope' has been destroyed.
	abstract Bool isDestroyed()

	** Returns a recursive list of all the Scopes this Scope inherits from.
	** The result list always starts with this Scope itself.
	** 
	** syntax: fantom
	** scope.inheritance() // --> ui, root, builtIn
	abstract Scope[] inheritance()
}


@Js
internal const class ScopeImpl : Scope {
	private  const OneShotLock 		destroyedLock
	private  const ServiceStore		serviceStore
	private  const AtomicBool		jailBroken		:= AtomicBool(false)
	internal const ScopeDefImpl		scopeDef
	override const RegistryImpl		registry
	override const ScopeImpl?		parent
	
	internal new make(RegistryImpl registry, ScopeImpl? parent, ScopeDefImpl scopeDef) {
		this.registry		= registry
		this.scopeDef		= scopeDef
		this.parent			= parent
		this.serviceStore	= ServiceStore(registry, scopeDef.id)
		this.destroyedLock	= OneShotLock(ErrMsgs.scopeDestroyed(id), ScopeDestroyedErr#)		
	}

	override Str id() {
		scopeDef.id
	}
	
	override Bool isThreaded() {
		scopeDef.threaded
	}

	override Scope[] inheritance() {
		scope  := (Scope?) this
		scopes := Scope[,]
		while (scope != null) {
			scopes.add(scope)
			scope = scope.parent
		}
		return scopes
	}

	override Obj? build(Type type, Obj?[]? ctorArgs := null, [Field:Obj?]? fieldVals := null) {
		destroyedCheck

		registry.opStack.push("Building", type.qname)
		try return registry.autoBuilder.autobuild(this, type, ctorArgs, fieldVals, null)
		catch (IocErr ie)	throw ie
		catch (Err err)		throw IocErr(err.msg, err)
		finally registry.opStack.pop
	}

	override Obj inject(Obj instance) {
		destroyedCheck

		registry.opStack.push("Injecting", instance.typeof.qname)
		try {
			plan := registry.autoBuilder.findFieldVals(this, instance.typeof, instance, null, null)			
			plan.each |val, field| {
				field.set(instance, field.isConst ? val.toImmutable : val)
			}
			registry.autoBuilder.callPostInjectionMethods(this, null, instance, instance.typeof)
			return instance
		}
		catch (IocErr ie)	throw ie
		catch (Err err)		throw IocErr(err.msg, err)
		finally registry.opStack.pop
	}

	override Obj? callMethod(Method method, Obj? instance, Obj?[]? args := null) {
		destroyedCheck

		registry.opStack.push("Calling method", method.qname)
		try {
			methodArgs := registry.autoBuilder.findFuncArgs(this, method.func, args, instance, null)
			return method.callOn(instance, methodArgs)
		}
		catch (IocErr ie)	throw ie
		catch (Err err)		throw IocErr(err.msg, err)
		finally registry.opStack.pop
	}

	override Obj? callFunc(Func func, Obj?[]? args := null) {
		destroyedCheck
		if (func.typeof.isGeneric)
			throw ArgErr("Can not call generic functions: ${func.typeof.signature}")

		registry.opStack.push("Calling func", func.typeof.signature)
		try {
			funcArgs := registry.autoBuilder.findFuncArgs(this, func, args, null, null)
			return func.callList(funcArgs)
		}
		catch (IocErr ie)	throw ie
		catch (Err err)		throw IocErr(err.msg, err)
		finally registry.opStack.pop
	}
	
	override Obj? serviceById(Str serviceId, Bool checked := true) {
		destroyedCheck		
		
		registry.opStack.push("Resolving ID", serviceId)
		registry.opStack.setServiceId(serviceId)
		try 	return serviceById_(serviceId, Str[,], checked)
		catch	(IocErr ie)	throw ie
		catch	(Err err)	throw IocErr(err.msg, err)
		finally registry.opStack.pop
	}

	internal Obj? serviceById_(Str serviceId, Str[] scopes, Bool checked := true) {
		serviceInstance := serviceStore.instanceById(serviceId)
		if (serviceInstance == null)
			return parent?.serviceById_(serviceId, scopes.add(id), checked)
				?: (checked ? throw ServiceNotFoundErr(ErrMsgs.scope_couldNotFindServiceById(serviceId, scopes.dup.add(id).reverse), services(scopes.dup.add(id).reverse)) : null)
		return serviceInstance.getOrBuild(this)
	}

	override Obj? serviceByType(Type serviceType, Bool checked := true) {
		destroyedCheck

		registry.opStack.push("Resolving Type", serviceType.qname)
		try		return serviceByType_(serviceType, Str[,], checked)
		catch	(IocErr ie)	throw ie
		catch	(Err err)	throw IocErr(err.msg, err)
		finally registry.opStack.pop
	}

	internal Obj? serviceByType_(Type serviceType, Str[] scopes, Bool checked := true) {
		serviceInstance := serviceStore.instanceByType(serviceType)
		if (serviceInstance == null)
			return parent?.serviceByType_(serviceType, scopes.add(id), checked)
				?: (checked ? throw ServiceNotFoundErr(ErrMsgs.scope_couldNotFindServiceByType(serviceType, scopes.dup.add(id).reverse), services(scopes.dup.add(id).reverse)) : null)
		registry.opStack.setServiceId(serviceInstance.def.id)
		return serviceInstance.getOrBuild(this)			
	}
	
	override Scope? createChild(Str scopeId, |Scope|? f := null) {
		destroyedCheck

		childScopeDef	:= registry.findScopeDef(scopeId, this)
		childScope 		:= ScopeImpl(registry, this, childScopeDef)
		
		if (f != null)
			registry.activeScopeStack.push(childScope)
		else
			// this isn't strictly needed, for it will never be checked, but it doesn't hurt to keep everything in check
			childScope.jailBroken.val = true

		errors := null as Err[]
		try {
			// if createHooks errors, we should still call destroyHooks, because *some* create hooks may have succeeded
			errors = childScopeDef.callCreateHooks(childScope)

			if (f != null && (errors == null || errors.isEmpty))
				f.call(childScope)
		} finally {
			if (f != null) {
				errs := childScope.destroyInternal
				if (errs != null) {
					if (errors == null)
						errors = Err[,]
					errors.addAll(errs)
				}
			}
		}
		
		if (errors != null && errors.size > 0)
			throw errors.first
		
		return f == null ? childScope : null
	}

	override This jailBreak() {
		destroyedCheck
		jailBroken.val = true
		return this
	}

	override Bool isDestroyed() {
		destroyedLock.locked
	}
	
	override Void destroy() {
		errors := _destroy
		if (errors != null && errors.size > 0)
			throw errors.first		
	}
	
	override Void asActive(|Scope| f) {
		registry.activeScopeStack.push(this)
		try		f(this)
		finally	registry.activeScopeStack.pop(this)
	}

	internal Err[]? destroyInternal() {
		jailBroken.val ? null : _destroy
	}

	internal Err[]? _destroy() {
		// keeping a thread safe / synchronised list of active children is only achievable using 
		// Actors or a couple of locking flags. Either way, the contention overhead for dealing 
		// with multiple threads (e.g. BedSheet) makes it unrealistic for what little gain it 
		// gives - primarily ensuring child scopes are destroyed before their parents, which is
		// only of concern if someone has destroy hooks on both scopes.
		//
		// An IoC module could easily be created to compensate for this if absolutely needed. 
		if (destroyedLock.locked) return null

		try {
			return scopeDef.callDestroyHooks(this)

		} finally {
			destroyedLock.lock
	
			serviceStore.destroy
			
			// only pop ourselves off the end of the stack
			registry.activeScopeStack.pop(this)
		}
	}

	internal Void destroyedCheck() {
		registry.shutdownLock.check
		destroyedLock.check

		// just in case someone forgets to destroy a jail broken scope
		// also allows active threaded scopes to check the status of the root scope during registry shutdown
		try	parent?.destroyedCheck
		catch (ScopeDestroyedErr err) {
			destroy
			throw err
		}
	}

	internal ServiceDefImpl? serviceDefById(Str serviceId, Bool checked) {
		instanceById(serviceId, Str[,], checked)?.def
	}

	internal ServiceDefImpl? serviceDefByType(Type serviceType, Bool checked) {
		instanceByType(serviceType, Str[,], checked)?.def
	}

	internal ServiceInstance? instanceById(Str serviceId, Str[] scopes, Bool checked) {
		serviceStore.instanceById(serviceId)
			?: (parent?.instanceById(serviceId, scopes.add(id), checked)
				?: (checked ? throw ServiceNotFoundErr(ErrMsgs.scope_couldNotFindServiceById(serviceId, scopes.dup.add(id).reverse), services(scopes.dup.add(id).reverse)) : null)
			)
	}

	internal ServiceInstance? instanceByType(Type serviceType, Str[] scopes, Bool checked) {
		serviceStore.instanceByType(serviceType)
			?: (parent?.instanceByType(serviceType, scopes.add(id), checked)
				?: (checked ? throw ServiceNotFoundErr(ErrMsgs.scope_couldNotFindServiceByType(serviceType, scopes.dup.add(id).reverse), services(scopes.dup.add(id).reverse)) : null)
			)
	}

	// just for the autobuild / service warning
	internal Bool containsServiceType(Type serviceType) {
		serviceStore.containsServiceType(serviceType) ? true : (parent?.containsServiceType(serviceType) ?: false)
	}
	
	private Str[] services(Str[] scopes) {
		scopes.map |scope| { registry.scopeIdLookup[scope].map { "$scope - $it" } }.flatten
	}
	
	override Str toStr() {
		"Scope: $id"
	}
}
