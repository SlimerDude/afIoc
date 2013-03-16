using concurrent

const class IocService : Service, ObjLocator {
	private static const Log 	log 	:= Log.get(IocService#.name)
	private const LocalStash 	stash	:= LocalStash(typeof)

	private const Bool			loadModulesFromIndexProps
	private const Type[]		moduleTypes
	
	new make(Bool loadModulesFromIndexProps, Type[] moduleTypes) {
		this.loadModulesFromIndexProps = loadModulesFromIndexProps
		this.moduleTypes = moduleTypes
	}
	
	override Void onStart() {
		log.info("Starting IOC...");
	
		try {
			regBuilder := RegistryBuilder()
			
			if (loadModulesFromIndexProps) {
				moduleNames := Env.cur.index("afIoc.module")
				moduleNames.each |moduleName| {
					regBuilder.addModule(Type.find(moduleName))
				}
			}
			
			regBuilder.addModules(moduleTypes)
			
			registry = regBuilder.build.startup
			
		} catch (Err e) {
			log.err("Err starting IOC", e)
		}
	}

	override Void onStop() {
		log.info("Stopping IOC...");
		registry.shutdown
	}
	
	
	
	// ---- Registry Methods ----------------------------------------------------------------------
	
	override Obj serviceById(Str serviceId) {
		registry.serviceById(serviceId)
	}
	
	override Obj serviceByType(Type serviceType) {
		registry.serviceByType(serviceType)
	}

	override Obj autobuild(Type type) {
		registry.autobuild(type)
	}
	
	override Obj injectIntoFields(Obj service) {
		registry.injectIntoFields(service)
	}
	
	
	
	// ---- Private -------------------------------------------------------------------------------
	
	Registry registry {
		get { stash["registry"] }
		private set { stash["registry"] = it }
	}
}

internal const class LocalStash {
	private const Str prefix
	
	new make(Type type) {
		this.prefix = type.qname
	}
	
	@Operator
	Obj? get(Str name, |->Obj|? valFunc := null) {
		val := Actor.locals[key(name)]
		if (val == null) {
			if (valFunc != null) {
				val = valFunc.call
				set(name, val)
			}
		}
		return val
	}

	@Operator
	Void set(Str name, Obj? value) {
		Actor.locals[key(name)] = value
	}
	
	private Str key(Str name) {
		return "${prefix}.${name}"
	}
}
