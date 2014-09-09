
** Use in services to inject classes that have not been defined as a service. 
** Instances are created via [Registry.autobuild()]`Registry#autobuild`.
** 
** @since 2.0.0
facet class Autobuild {
	
	const Bool createProxy

	const Type? implType
	
	const Obj?[]? ctorArgs
	
	const [Field:Obj?]? fieldVals
}
