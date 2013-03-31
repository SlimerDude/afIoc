
internal const class ModuleDefImpl : ModuleDef {
	private const static Log log := Utils.getLog(ModuleDefImpl#)
	
	** prefix used to identify service builder methods
	private static const Str 			BUILD_METHOD_NAME_PREFIX 		:= "build"

	** prefix used to identify service contribution methods
	private static const Str 			CONTRIBUTE_METHOD_NAME_PREFIX 	:= "contribute"

	private static const Method[]		OBJECT_METHODS 					:= Obj#.methods
	
	override 	const Type 				moduleType
	override 	const Str:ServiceDef	serviceDefs
	override 	const ContributionDef[]	contributionDefs
	

	new make(OpTracker tracker, Type moduleType) {
		this.moduleType = moduleType

		tracker.track("Inspecting module $moduleType.qname") |->| {
			serviceDefs := Str:ServiceDef[:] { caseInsensitive = true }
			contribDefs	:= ContributionDef[,]
			
			methods := moduleType.methods.exclude |method| { OBJECT_METHODS.contains(method) || method.isCtor }
	
			grind(tracker, serviceDefs, contribDefs, methods)
			bind(tracker, serviceDefs, methods)
			
			contributionDefs=[,]
	
			// verify that every public method is meaningful to IoC. Any remaining methods may be 
			// typos, i.e. "createFoo" instead of "buildFoo"
			methods = methods.exclude { !it.isPublic }
			if (!methods.isEmpty)
				throw IocErr(IocMessages.unrecognisedModuleMethods(moduleType, methods))
			
			this.serviceDefs = serviceDefs
			this.contributionDefs = contribDefs
		}
	}


	// ---- ModuleDef Methods ---------------------------------------------------------------------
	
	override Str moduleId() {
		moduleType.qname
	}
	
	override Str toStr() {
		"Def for ${moduleId}"
	}
	
	
	// ---- Private Methods -----------------------------------------------------------------------

	private Void grind(OpTracker tracker, Str:ServiceDef serviceDefs, ContributionDef[]	contribDefs, Method[] remainingMethods) {
		methods := moduleType.methods.dup.sort |Method a, Method b -> Int| { 
			a.name <=> b.name 
		}

		methods.each |method| {
			
			if (method.name.startsWith(BUILD_METHOD_NAME_PREFIX)) {
				tracker.track("Found builder method $method.qname") |->| {
					addServiceDefFromMethod(tracker, serviceDefs, method)
					remainingMethods.remove(method)
				}
			}
			
			if (method.hasFacet(Contribute#)) {
				tracker.track("Found contribution method $method.qname") |->| {					
					addContribDefFromMethod(tracker, contribDefs, method)
					remainingMethods.remove(method)
				}
			}

			// TODO: @Startup
//			if (method.hasFacet(Startup#))) {
//				addStartupDef(method)
//				remainingMethods.remove(method)
//				return
//			}
		}
	}
	
	
	// ---- Service Contribution Methods ----------------------------------------------------------

	private Void addContribDefFromMethod(OpTracker tracker, ContributionDef[] contribDefs, Method method) {
		if (!method.isStatic)
			throw IocErr(IocMessages.contributionMethodMustBeStatic(method))
		if (method.params.isEmpty || (method.params[0].type != OrderedConfig# && method.params[0].type != MappedConfig#))
			throw IocErr(IocMessages.contributionMethodMustTakeConfig(method))
		
		contribute := Utils.getFacetOnSlot(method, Contribute#) as Contribute

		contribDef	:= StandardContributionDef {
			it.serviceId	= extractServiceIdFromContributionMethod(contribute, method)
			it.serviceType	= contribute.serviceType
			it.optional		= contribute.optional
			it.method		= method
		}
		
		serviceName := (contribDef.serviceId != null) ? "id '$contribDef.serviceId'" : "type '$contribDef.serviceType'" 
		tracker.log("Adding service contribution for service $serviceName")
		contribDefs.add(contribDef)
	}
	
	private Str? extractServiceIdFromContributionMethod(Contribute contribute, Method method) {
		
		if (contribute.serviceId != null && contribute.serviceType != null)
			throw IocErr(IocMessages.contribitionHasBothIdAndType(method))
		
		if (contribute.serviceId != null)
			return contribute.serviceId
		
		// resolve service from type - not id
		if (contribute.serviceType != null)
			return null
		
		serviceId := stripMethodPrefix(method, CONTRIBUTE_METHOD_NAME_PREFIX)

        if (serviceId.isEmpty)
            throw IocErr(IocMessages.contributionMethodDoesNotDefineServiceId(method))
		
		return serviceId
	}	
	
	
	// ---- Service Builder Methods ---------------------------------------------------------------
	
	private Void addServiceDefFromMethod(OpTracker tracker, Str:ServiceDef serviceDefs, Method method) {
		
		scope := method.returns.isConst ? ScopeScope.perApplication : ScopeScope.perThread
		
		if (method.hasFacet(Scope#))
			scope = (Utils.getFacetOnSlot(method, Scope#) as Scope).scope
		
		serviceDef	:= StandardServiceDef {
			it.serviceId 	= extractServiceIdFromBuilderMethod(method)
			it.moduleId 	= this.moduleId
			it.serviceType	= method.returns
//			it.isEagerLoad 	= method.hasFacet(EagerLoad#)
			it.description	= "'$serviceId' : Builder method $method.qname"
			it.scope 		= scope 
			
			sId 			:= it.serviceId
			it.source 		= |InjectionCtx ctx -> Obj| {
				ctx.track("Creating Serivce '$sId' via a builder method '$method.qname'") |->Obj| {
					log.info("Creating Service '$sId'")
					return InjectionUtils.callMethod(ctx, method, null)
				}
			}			
		}
		addServiceDef(tracker, serviceDefs, serviceDef)
	}	

    private Void addServiceDef(OpTracker tracker, Str:ServiceDef serviceDefs, ServiceDef serviceDef) {
		tracker.log("Adding service definition for service '$serviceDef.serviceId' -> ${serviceDef.serviceType.qname}")
		
		ServiceDef? existing := serviceDefs[serviceDef.serviceId]
		if (existing != null) {
			throw IocErr(IocMessages.buildMethodConflict(serviceDef.serviceId, serviceDef.toStr, existing.toStr))
		}
		
		serviceDefs[serviceDef.serviceId] = serviceDef
    }	

	private Str extractServiceIdFromBuilderMethod(Method method) {
		serviceId := stripMethodPrefix(method, BUILD_METHOD_NAME_PREFIX)

        if (serviceId.isEmpty)
            throw IocErr(IocMessages.buildMethodDoesNotDefineServiceId(method))
		
		return serviceId
	}

	
	// ---- Binder Methods ------------------------------------------------------------------------

	private Void bind(OpTracker tracker, Str:ServiceDef serviceDefs, Method[] remainingMethods) {
		Method? bindMethod := moduleType.method("bind", false)

		if (bindMethod == null)
			// No problem! Many modules will not have such a method.
			return

		tracker.track("Found binder method $bindMethod.qname") |->| {
			if (!bindMethod.isStatic)
				throw IocErr(IocMessages.bindMethodMustBeStatic(bindMethod))

			if (bindMethod.params.size != 1 || !bindMethod.params[0].type.fits(ServiceBinder#))
				throw IocErr(IocMessages.bindMethodWrongParams(bindMethod))

			binder := ServiceBinderImpl(bindMethod, this) |ServiceDef serviceDef| {
				addServiceDef(tracker, serviceDefs, serviceDef)
			}

			try {
				bindMethod.call(binder)
			} catch (IocErr e) {
				throw e
			} catch (Err e) {
				throw IocErr(IocMessages.errorInBindMethod(bindMethod.qname, e), e)
			}

			binder.finish
			remainingMethods.remove(bindMethod)
		}
	}

	private static Str stripMethodPrefix(Method method, Str prefix) {
		if (method.name.lower.startsWith(prefix.lower))
			return method.name[prefix.size..-1]
		else
			return ""
	}
}

