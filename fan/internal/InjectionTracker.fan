using concurrent::Actor

internal class InjectionTracker {

	private static const Str 	trackerId		:= "afIoc.injectionTracker"
	private static const Str 	serviceDefId	:= "afIoc.serviceDef"
	private static const Str 	confProviderId	:= "afIoc.configProvider"
	private static const Str 	injectionCtxId	:= "afIoc.injectionCtx"
	
	private OpTracker 			opTracker

	** nullable for testing only
	new make(OpTracker tracker := OpTracker()) {
		this.opTracker	= tracker
	}

	static Obj? withCtx(OpTracker tracker, |->Obj?| f) {
		ThreadStack.pushAndRun(trackerId, InjectionTracker(tracker), f)
	}

	static Obj? track(Str description, |->Obj?| operation) {
		if (ThreadStack.peek(trackerId, false) == null) {
			return withCtx(OpTracker()) |->Obj?| {
				return tracker.track(description, operation)
			}
		} else
			return tracker.track(description, operation)
	}

	static Void log(Str msg) {
		tracker.log(msg)
	}

	static Void logExpensive(|->Str| msgFunc) {
		tracker.logExpensive(msgFunc)
	}

	private static OpTracker tracker() {
		((InjectionTracker) ThreadStack.peek(trackerId, true)).opTracker
	}

	// ---- Recursion Detection ----------------------------------------------------------------------------------------

	static Obj? withServiceDef(ServiceDef def, |->Obj?| operation) {
		ThreadStack.pushAndRun(serviceDefId, def) |->Obj?| {
			// check for recursion
			ThreadStack.elements(serviceDefId).eachRange(0..<-1) |ServiceDef ele| { 
				if (ele.serviceId == def.serviceId)
					throw IocErr(IocMessages.serviceRecursion(ThreadStack.elements(serviceDefId).map |ServiceDef sd->Str| { sd.serviceId }))
			}

			return operation.call()
		}
	}

	static ServiceDef? peekServiceDef() {
		ThreadStack.peek(serviceDefId, false)
	}

	// ---- Injection Ctx ----------------------------------------------------------------------------------------------

	static Obj? doingDependencyByType(Type dependencyType, |->Obj?| func) {
		ctx := InjectionCtx(InjectionKind.dependencyByType) {
			it.dependencyType = dependencyType
		}
		return ThreadStack.pushAndRun(injectionCtxId, ctx, func)
	}
	
	static Obj? doingFieldInjection(Obj injectingInto, Field field, |->Obj?| func) {
		ctx := InjectionCtx(InjectionKind.fieldInjection) {
			it.injectingInto	= injectingInto
			it.injectingIntoType= injectingInto.typeof
			it.dependencyType	= field.type
			it.field			= field
			it.fieldFacets		= field.facets
		}
		return ThreadStack.pushAndRun(injectionCtxId, ctx, func)
	}

	static Obj? doingFieldInjectionViaItBlock(Type injectingIntoType, Field field, |->Obj?| func) {
		ctx := InjectionCtx(InjectionKind.fieldInjectionViaItBlock) {
			it.injectingIntoType= injectingIntoType
			it.dependencyType	= field.type
			it.field			= field
			it.fieldFacets		= field.facets
		}
		return ThreadStack.pushAndRun(injectionCtxId, ctx, func)
	}

	static Obj? doingMethodInjection(Obj? injectingInto, Method method, |->Obj?| func) {
		ctx := InjectionCtx(InjectionKind.methodInjection) {
			it.injectingInto	= injectingInto
			it.injectingIntoType= method.parent
			it.method			= method
			it.methodFacets		= method.facets
			// this will get replaced with the param value
			it.dependencyType	= Void#
		}
		return ThreadStack.pushAndRun(injectionCtxId, ctx, func)
	}

	static Obj? doingCtorInjection(Type injectingIntoType, Method ctor, [Field:Obj?]? fieldVals, |->Obj?| func) {
		ctx := InjectionCtx(InjectionKind.ctorInjection) {
			it.injectingIntoType= injectingIntoType
			it.method			= ctor
			it.methodFacets		= ctor.facets
			it.ctorFieldVals	= fieldVals
			// this will get replaced with the param value
			it.dependencyType	= Void#
		}
		return ThreadStack.pushAndRun(injectionCtxId, ctx, func)
	}

	static Obj? doingParamInjection(Param param, Int index, |->Obj?| func) {
		ctx := (InjectionCtx) ThreadStack.peek(injectionCtxId)
		ctx.dependencyType		= param.type
		ctx.methodParam			= param
		ctx.methodParamIndex	= index
		return func.call
	}

	static InjectionCtx injectionCtx() {
		ThreadStack.peek(injectionCtxId)
	}	
}
