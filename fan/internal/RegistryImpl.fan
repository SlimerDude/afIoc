using concurrent
using afPlastic::PlasticCompiler

internal const class RegistryImpl : Registry, ObjLocator {
	private const static Log log := Utils.getLog(RegistryImpl#)

	private const OneShotLock 			startupLock 	:= OneShotLock(IocMessages.registryStarted)
	private const OneShotLock 			shutdownLock	:= OneShotLock(|->| { throw IocShutdownErr(IocMessages.registryShutdown) })
	private const Module[]				modules
	private const Str:ServiceDef		serviceDefs		:= Utils.makeMap(Str#, ServiceDef#) 
	private const DependencyProviders?	depProSrc
	private const Duration				startTime
			const AtomicBool			logServices		:= AtomicBool(false)
			const AtomicBool			logBanner		:= AtomicBool(false)
			const AtomicBool			sayGoodbye		:= AtomicBool(false)	
	
	new make(OpTracker tracker, ModuleDef[] moduleDefs, [Str:Obj?] options) {
		this.startTime	= tracker.startTime
		serviceDefs		:= (Str:ServiceDef) Utils.makeMap(Str#, ServiceDef#)
		modules			:= Module[,]		
		threadLocalMgr 	:= ThreadLocalManagerImpl()
		
		// new up Built-In services ourselves (where we can) to cut down on debug noise
		tracker.track("Defining Built-In services") |->| {
			
			builtInModuleDef := ModuleDef(tracker, IocModule#)
			builtInModuleDef.serviceDefs[IocConstants.ctorItBlockBuilder] = SrvDef {
				it.moduleId		= IocModule#.qname
				it.id 			= IocConstants.ctorItBlockBuilder
				it.type 		= |This|#
				it.scope		= ServiceScope.perInjection
				it.desc 		= "$it.id : Autobuilt. Always."
				it.buildData	= |->Obj| {
					InjectionUtils.makeCtorInjectionPlan(InjectionTracker.injectionCtx.injectingIntoType)
				}
			}
			builtInModuleDef.serviceDefs.each { it.builtIn = true }
			
			readyMade := [
				Registry#			: this,
				RegistryMeta#		: RegistryMetaImpl(options, moduleDefs.map { it.moduleType }),
				ThreadLocalManager#	: threadLocalMgr
			]
			
			builtInModule := ModuleImpl(this, threadLocalMgr, builtInModuleDef, readyMade)
			modules.add(builtInModule)
		}

		// this IoC trace makes more sense when we throw dup id errs
		tracker.track("Consolidating service definitions") |->| {
			srvDefs	:= (SrvDef[]) moduleDefs.map { it.serviceDefs.vals }.flatten
			ovrDefs	:= (SrvDef[]) moduleDefs.map { it.serviceOverrides }.flatten
			
			// we could use Map.addList(), but do it the long way round so we get a nice error on dups
			services	:= Str:SrvDef[:] { caseInsensitive = true}
			srvDefs.each {
				if (services.containsKey(it.id))
					throw IocErr(IocMessages.serviceAlreadyDefined(it.id, it, services[it.id]))
				services[it.id] = it
			}

			// we could use Map.addList(), but do it the long way round so we get a nice error on dups
			overrides	:= Str:SrvDef[:] { caseInsensitive = true}
			ovrDefs.each {
				if (overrides.containsKey(it.id))
					throw IocErr(IocMessages.onlyOneOverrideAllowed(it.id, it, overrides[it.id]))
				overrides[it.id] = it
			}

			tracker.track("Applying service overrides") |->| {
				keys := Utils.makeMap(Str#, Str#)
				services.keys.each { keys[it] = it }
	
				// normalise keys -> map all keys to orig key and apply overrides
				// code nabbed from Configuration
				found		:= true
				while (!overrides.isEmpty && found) {
					found = false
					overrides = overrides.exclude |over, existingKey| {
						overrideKey := over.overrideRef
						if (keys.containsKey(existingKey)) {
							if (keys.containsKey(overrideKey))
								throw IocErr(IocMessages.overrideAlreadyDefined(over.overrideRef, over, services[keys[existingKey]]))

							keys[overrideKey] = keys[existingKey]
							found = true
							
							tracker.log("'${overrideKey}' overrides '${existingKey}'")
							srvDef := services[keys[existingKey]]						
							srvDef.applyOverride(over)
	
							return true
						} else {
							return false
						}
					}
				}
	
				overrides = overrides.exclude { it.overrideOptional }
	
				if (!overrides.isEmpty) {
					keysNotFound := overrides.keys.join(", ")
					throw ServiceNotFoundErr(IocMessages.serviceIdNotFound(keysNotFound), services.keys)
				}
			}
		}
		
		tracker.track("Consolidating module definitions") |->| {
			moduleDefs.each |moduleDef| {
				module := ModuleImpl(this, threadLocalMgr, moduleDef, null)
				modules.add(module)
			}
			// loop here to include the BuiltIn IocModule
			modules.each |module| {
				module.serviceDefs.each |def| {
					serviceDefs[def.serviceId] = def
				}
			}
		}		

		// set before we validate the contributions
		this.modules 		= modules
		this.serviceDefs	= serviceDefs
		
		tracker.track("Validating contribution definitions") |->| {
			moduleDefs.each {
				it.contribDefs.each {
					if (!it.optional) {	// no warnings / errors for optional contributions
						if (it.serviceId != null)
							if (serviceDefById(it.serviceId) == null)
								throw IocErr(IocMessages.contributionMethodServiceIdDoesNotExist(it.method, it.serviceId))
						if (it.serviceType != null)
							if (serviceDefByType(it.serviceType) == null)
								throw IocErr(IocMessages.contributionMethodServiceTypeDoesNotExist(it.method, it.serviceType))
					}
				}
			}
		}

		tracker.track("Validating advice definitions") |->| {
			advisableServices := serviceDefs.vals.findAll { it.proxiable }
			moduleDefs.each {
				it.adviceDefs.each |adviceDef| {
					if (adviceDef.optional)
						return
					matches := advisableServices.any |def| { 
						adviceDef.matchesService(def)  
					}
					if (!matches)
						throw IocErr(IocMessages.adviceDoesNotMatchAnyServices(adviceDef, advisableServices.map { it.serviceId }))
				}
			}
		}

		InjectionTracker.withCtx(this, tracker) |->Obj?| {
			depProSrc = trackServiceById(DependencyProviders#.qname, true)
			return null
		}		
	}


	// ---- Registry Methods ----------------------------------------------------------------------

	override This startup() {
		shutdownLock.check
		startupLock.lock

		buildTime	:= (Duration.now - startTime).toMillis.toLocale("#,###")
		then 		:= Duration.now
		
		// Do dat startup!
		startup 	:= (RegistryStartup) serviceById(RegistryStartup#.qname)
		startup.startup(OpTracker())
		startupTime	:= (Duration.now - then).toMillis.toLocale("#,###")

		// We're alive! Shout it out to the world!
		msg			:= ""

		// we do this here (and not in the contribution) because we want to print last
		// (to get the most upto date stats)
		if (logServices.val)
			msg += startup.printServiceList
		
		if (logBanner.val) {
			msg += startup.printBanner
			msg += "IoC Registry built in ${buildTime}ms and started up in ${startupTime}ms\n"
		}
		
		if (!msg.isEmpty)
			log.info(msg)

		return this
	}
	
	override This shutdown() {
		shutdownLock.check
		then 		:= Duration.now
		shutdownHub := (RegistryShutdown)	serviceById(RegistryShutdown#.qname)
		threadMan 	:= (ThreadLocalManager)	serviceById(ThreadLocalManager#.qname)
		actorPools	:= (ActorPools) 	 	serviceById(ActorPools#.qname)

		// Registry shutdown commencing...
		shutdownHub.shutdown
		shutdownLock.lock

		// Registry shutdown complete.
		threadMan.cleanUpThread
		modules.each { it.shutdown }
		actorPools[IocConstants.systemActorPool].stop.join(10sec)
		
		shutdownTime := (Duration.now - then).toMillis.toLocale("#,###")
		if (sayGoodbye.val) {
			log.info("IoC shutdown in ${shutdownTime}ms")
			log.info("\"Goodbye!\" from afIoc!")
		}
		return this
	}

	override Obj? serviceById(Str serviceId, Bool checked := true) {
		return Utils.stackTraceFilter |->Obj?| {
			shutdownLock.check
			return InjectionTracker.withCtx(this, null) |->Obj?| {   
				return InjectionTracker.track("Locating service by ID '$serviceId'") |->Obj?| {
					return trackServiceById(serviceId, checked)
				}
			}
		}
	}

	override Obj? dependencyByType(Type dependencyType, Bool checked := true) {
		return Utils.stackTraceFilter |->Obj?| {
			shutdownLock.check
			return InjectionTracker.withCtx(this, null) |->Obj?| {
				return InjectionTracker.track("Locating dependency by type '$dependencyType.qname'") |->Obj?| {
					return InjectionTracker.doingDependencyByType(dependencyType) |->Obj?| {
						// as ctx is brand new, this won't return null
						return trackDependencyByType(dependencyType, checked)
					}
				}
			}
		}
	}

	** see http://fantom.org/sidewalk/topic/2149
	override Obj autobuild(Type type2, Obj?[]? ctorArgs := null, [Field:Obj?]? fieldVals := null) {
		return Utils.stackTraceFilter |->Obj| {
			shutdownLock.check
			return InjectionTracker.withCtx(this, null) |->Obj?| {
				return trackAutobuild(type2, ctorArgs, fieldVals)
			}
		}
	}
	
	override Obj createProxy(Type mixinType, Type? implType := null, Obj?[]? ctorArgs := null, [Field:Obj?]? fieldVals := null) {
		return Utils.stackTraceFilter |->Obj?| {
			shutdownLock.check
			return InjectionTracker.withCtx(this, null) |->Obj?| {
				return InjectionTracker.track("Creating proxy for ${mixinType.qname}") |->Obj?| {
					return trackCreateProxy(mixinType, implType, ctorArgs, fieldVals)
				}
			}
		}
	}

	override Obj injectIntoFields(Obj object) {
		return Utils.stackTraceFilter |->Obj| {
			shutdownLock.check
			return InjectionTracker.withCtx(this, null) |->Obj?| {
				return trackInjectIntoFields(object)
			}
		}
	}

	override Obj? callMethod(Method method, Obj? instance, Obj?[]? providedMethodArgs := null) {
		try {
			return Utils.stackTraceFilter |->Obj?| {
				shutdownLock.check
				return InjectionTracker.withCtx(this, null) |->Obj?| {
					return InjectionTracker.track("Calling method '$method.signature'") |->Obj?| {
						return trackCallMethod(method, instance, providedMethodArgs)
					}
				}
			}
		} catch (IocErr iocErr) {
			unwrapped := Utils.unwrap(iocErr)
			// if unwrapped is still an IocErr then re-throw the original
			throw (unwrapped is IocErr) ? iocErr : unwrapped
		}
	}

	override Str:ServiceDefinition serviceDefinitions() {
		stats := Str:ServiceDefinition[:]	{ caseInsensitive = true }
		modules.each { stats.addAll(it.serviceStats) }
		return stats
	}	

	// ---- ObjLocator Methods --------------------------------------------------------------------

	override Obj? trackServiceById(Str serviceId, Bool checked) {
		serviceDef := serviceDefById(serviceId)
		if (serviceDef == null)
			return checked ? throw ServiceNotFoundErr(IocMessages.serviceIdNotFound(serviceId), serviceIds) : null
		return serviceDef.getService(false)
	}

	override Obj? trackDependencyByType(Type dependencyType, Bool checked) {

		// ask dependency providers first, for they may dictate dependency scope
		ctx := InjectionTracker.injectionCtx
		if (depProSrc?.canProvideDependency(ctx) ?: false) {
			dependency := depProSrc.provideDependency(ctx)
			InjectionTracker.logExpensive |->Str| { "Found Dependency via Provider : '$dependency?.typeof'" }
			return dependency
		}

		serviceDef := serviceDefByType(dependencyType)
		if (serviceDef != null) {
			InjectionTracker.logExpensive |->Str| { "Found Service '$serviceDef.serviceId'" }
			return serviceDef.getService(false)
		}

		config := InjectionTracker.provideConfig(dependencyType)
		if (config != null) {
			InjectionTracker.logExpensive |->Str| { "Found Configuration '$config.typeof.signature'" }
			return config
		}

		return checked ? throw IocErr(IocMessages.noDependencyMatchesType(dependencyType)) : null
	}

	override Obj trackAutobuild(Type type, Obj?[]? ctorArgs, [Field:Obj?]? fieldVals) {
		Type? implType := type
		
		if (implType.isAbstract) {
			implType 	= Type.find("${type.qname}Impl", false)
			if (implType == null)
				throw IocErr(IocMessages.autobuildTypeHasToInstantiable(type))
		}		
		
		// create a dummy serviceDef - this will be used by CtorItBlockBuilder to find the type being built
		serviceDef := ServiceDef.makeStandard() {
			it.serviceId 		= "${type.name}Autobuild"
			it.serviceType 		= type
			it.serviceScope		= ServiceScope.perInjection
			it.description 		= "$type.qname : Autobuild"
			it.serviceBuilder	= |->Obj?| { return null }.toImmutable
		}		
		
		return InjectionTracker.withServiceDef(serviceDef) |->Obj?| {
			return InjectionUtils.autobuild(implType, ctorArgs, fieldVals)
		}
	}

	override Obj trackCreateProxy(Type mixinType, Type? implType, Obj?[]? ctorArgs, [Field:Obj?]? fieldVals) {
		spb := (ServiceProxyBuilder) trackServiceById(ServiceProxyBuilder#.qname, true)
		
		serviceTypes := ServiceBinderImpl.verifyServiceImpl(mixinType, implType)
		mixinT 	:= serviceTypes[0] 
		implT 	:= serviceTypes[1]
		
		if (!mixinT.isMixin)
			throw IocErr(IocMessages.bindMixinIsNot(mixinT))

		// create a dummy serviceDef
		serviceDef := ServiceDef.makeStandard() {
			it.serviceId 		= "${mixinT.name}CreateProxy"
			it.serviceType 		= mixinT
			it.serviceScope		= ServiceScope.perInjection
			it.description 		= "$mixinT.qname : Create Proxy"
			it.serviceBuilder	= |->Obj| { autobuild(implT, ctorArgs, fieldVals) }.toImmutable
		}

		return spb.createProxyForMixin(serviceDef)
	}
	
	override Obj trackInjectIntoFields(Obj object) {
		return InjectionUtils.injectIntoFields(object)
	}

	override Obj? trackCallMethod(Method method, Obj? instance, Obj?[]? providedMethodArgs) {
		return InjectionUtils.callMethod(method, instance, providedMethodArgs)
	}

	override ServiceDef? serviceDefById(Str serviceId) {
		// attempt a qualified search first
		serviceDef := serviceDefs[serviceId]
		if (serviceDef != null)
			return serviceDef

		serviceDefs := serviceDefs.vals.findAll { it.matchesId(serviceId) }
		if (serviceDefs.size > 1)
			throw IocErr(IocMessages.multipleServicesDefined(serviceId, serviceDefs.map { it.serviceId }))
		
		return serviceDefs.isEmpty ? null : serviceDefs.first
	}

	override ServiceDef? serviceDefByType(Type serviceType) {
		serviceDefs := serviceDefs.vals.findAll { it.matchesType(serviceType) }

		if (serviceDefs.size > 1) {
			// if exists, return the default service, the one with the qname as its serviceId 
			lastChance := serviceDefs.find { it.serviceId.equalsIgnoreCase(serviceType.qname) }
			return lastChance ?: throw IocErr(IocMessages.manyServiceMatches(serviceType, serviceDefs.map { it.serviceId }))
		}

		return serviceDefs.isEmpty ? null : serviceDefs[0]
	}

	override Contribution[] contributionsByServiceDef(ServiceDef serviceDef) {
		modules.map {
			it.contributionsByServiceDef(serviceDef)
		}.flatten
	}

	override AdviceDef[] adviceByServiceDef(ServiceDef serviceDef) {
		modules.map {
			it.adviceByServiceDef(serviceDef)
		}.flatten
	}
	
	override Str[] serviceIds() {
		serviceDefs.keys
	}
}
