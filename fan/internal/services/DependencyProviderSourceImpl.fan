
** @since 1.1.0
internal const class DependencyProviderSourceImpl : DependencyProviderSource {
	private const DependencyProvider[] dependencyProviders

	new make(DependencyProvider[] dependencyProviders, Registry registry) {
		this.dependencyProviders = dependencyProviders.toImmutable
		
		// eager load all dependency providers else recursion err (app hangs) when creating DPs 
		// with lazy services
		ctx := InjectCtx(InjectionType.dependencyByType) { it.dependencyType = Void# }.toProviderCtx
		dependencyProviders.each { it.canProvide(ctx) }
	}

	override Bool canProvideDependency(ProviderCtx ctx) {
		dependencyProviders.any |provider->Bool| {
			// providers can't provide themselves!
			if (ctx.dependencyType.fits(provider.typeof))
				return false
			return provider.canProvide(ctx) 
		}		
	}

	override Obj? provideDependency(ProviderCtx ctx) {
		dps := dependencyProviders.findAll { it.canProvide(ctx) }

		if (dps.isEmpty)
			return null
		
		if (dps.size > 1)
			throw IocErr(IocMessages.onlyOneDependencyProviderAllowed(ctx.dependencyType, dps.map { it.typeof }))
		
		dependency := dps[0].provide(ctx)
		
		if (dependency == null) {
			if (!ctx.dependencyType.isNullable )
				throw IocErr(IocMessages.dependencyDoesNotFit(dependency.typeof, ctx.dependencyType))
		} else {
			if (!dependency.typeof.fits(ctx.dependencyType))
				throw IocErr(IocMessages.dependencyDoesNotFit(dependency.typeof, ctx.dependencyType))
		}

		return dependency
	}
}
