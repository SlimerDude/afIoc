
internal mixin Module {

	** Usually the qualified name of the Module Type 
	abstract Str moduleId() 
	
	** Returns the service definitions for the given service id
	abstract ServiceDef? serviceDefByQualifiedId(Str serviceId)

	abstract ServiceDef[] serviceDefsById(Str serviceId, Str unqualifiedId)

	** Locates the defs of all services that implement the provided service type, or whose service 
	** type is assignable to the provided service type (is a super-class or super-mixin).
    abstract ServiceDef[] serviceDefsByType(Type serviceType)

	abstract Contribution[] contributionsByServiceDef(ServiceDef serviceDef)

	abstract AdviceDef[] adviceByServiceDef(ServiceDef serviceDef)
	
	** Locates (and builds if necessary) a service given a service id
	abstract Obj? service(Str serviceId, Bool returnReal)

	abstract Str:ServiceStat serviceStats()
	
	abstract Void clear()

	abstract Bool hasServices()
}
