
** (Service) - Override a defined service with your own implementation. 
** 
** pre>
**   static Void bind(ServiceBinder binder) {
**     binder.bindImpl(PieAndChips#).withId("dinner")
**   }
** 
**   @Contribute
**   static Void contributeServiceOverride(MappedConfig conf) {
**     conf["dinner"] = conf.autobuild(PieAndMash#)
**   }
** <pre
**
** Note at present you can not override `perThread` scoped services and non-const (not immutable) 
** services. 
**  
** @since 1.2
** 
** @uses MappedConfig of 'Str:Obj' (serviceId:overrideImpl)
const mixin ServiceOverride {
	
	abstract Obj? getOverride(Str serviceId)
}



** @since 1.2.0
internal const class ServiceOverrideImpl : ServiceOverride {
	
	private const Str:Obj overrides
	
	new make(Str:Obj overrides, Registry registry) {
		overrides.each |service, id| {			
			existingDef := ((ObjLocator) registry).serviceDefById(id)
			if (existingDef == null)
				throw IocErr(IocMessages.serviceOverrideDoesNotExist(id, service.typeof))

			if (!service.typeof.fits(existingDef.serviceType))
				throw IocErr(IocMessages.serviceOverrideDoesNotFitServiceDef(id, service.typeof, existingDef.serviceType))
			
			if (!service.isImmutable)
				throw IocErr(IocMessages.serviceOverrideNotImmutable(id, service.typeof))
		}
		
		this.overrides = overrides
	}
	
	override Obj? getOverride(Str serviceId) {
		overrides[serviceId]
	}
}