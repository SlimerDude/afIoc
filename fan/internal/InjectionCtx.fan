
internal class InjectionCtx {
	
	private ServiceDef[]			defStack		:= [,]
	private DependencyProvider[]	providerStack	:= [,]
	OpTracker 						tracker			:= OpTracker()
	ObjLocator? 					objLocator
	
	new make(ObjLocator? objLocator) {
		this.objLocator = objLocator
	}

	Obj? track(Str description, |->Obj?| operation) {
		tracker.track(description, operation)
	}

	Void logExpensive(|->Str| msg) {
		tracker.logExpensive(msg)
	}
	
	Void log(Str description) {
		tracker.log(description)
	}

	Obj? withServiceDef(ServiceDef def, |->Obj?| operation) {
		// check for allowed scope
		if (defStack.peek?.scope == ServiceScope.perApplication && def.scope == ServiceScope.perThread)
			throw IocErr(IocMessages.threadScopeInAppScope(defStack.peek.serviceId, def.serviceId))
		
		defStack.push(def)
		
		try {
			// check for recursion
			defStack[0..<-1].each { 
				if (it.serviceId == def.serviceId)
					throw IocErr(IocMessages.serviceRecursion(defStack.map { it.serviceId }))
			}
			
			return operation()
			
		} finally {
			defStack.pop			
		}
	}
	
	Obj? withConfigProvider(DependencyProvider provider, |->Obj?| operation) {
		providerStack.push(provider)
		try {
			return operation()
		} finally {			
			providerStack.pop
		}
	}
	
	Obj? provideDependency(Type dependencyType) {
		// jus' passin' thru!
		providerStack.peek?.provide(this, dependencyType)
	}
}
