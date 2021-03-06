
@Js
internal class BugFixes : IocTest {
	
	Void testServiceImplsCanBeInjected() {
		reg := threadScope { addService(T_MyService79#).withId(T_MyService79Impl#.qname).withAliasType(T_MyService79Impl#) }
		
		// should have always worked
		s79 := reg.serviceById(T_MyService79Impl#.qname)
		verifyEq(s79.typeof, T_MyService79Impl#)

		// should have always worked
		s79 = reg.serviceByType(T_MyService79#)
		verifyEq(s79.typeof, T_MyService79Impl#)

		// the bug / enhancement
		s79 = reg.serviceByType(T_MyService79Impl#)
		verifyEq(s79.typeof, T_MyService79Impl#)
		
		reg.registry.shutdown
	}

	Void testServiceMixinsCanBeInjected() {
		reg := threadScope { addService(T_MyService79Impl#).withId(T_MyService79#.qname).withAliasType(T_MyService79#) }
		
		// should have always worked
		s79 := reg.serviceById(T_MyService79#.qname)
		verifyEq(s79.typeof, T_MyService79Impl#)

		// There's no reason *why* mixins can't be injected - as long as the actual service implements it
		// the bug / enhancement
		s79 = reg.serviceByType(T_MyService79#)
		verifyEq(s79.typeof, T_MyService79Impl#)
		
		reg.registry.shutdown
	}
	
	Void testOrderedPlaceholdersAllowedOnNonStrConfig() {
		reg := threadScope { addModule(T_MyModule85#) }
		t70	:= (T_MyService70) reg.serviceById("t70")
		verifyNotNull(t70)
	}

	Void testDupServicesWithDiffIds() {
		reg := threadScope { addModule(T_MyModule98#) }
		
		s1 := reg.serviceById(T_MyService89#.qname)
		s2 := reg.serviceById("PillowRoutes")
		verifyNotEq(s1, s2)
		
		t1 := reg.serviceById(T_MyService89#.qname)
		verifyEq(t1, s1)
	}

	Void testThreadedServicesCanNotBeInjectedIntoCtor() {
		reg := threadScope { addModule(T_MyModule100#) }
		// by default, lets not mix up the scopes 'cos it's confusing
		// if they really want to, they can use registry.activeScope for resolution
		verifyIocErrMsg(ErrMsgs.autobuilder_couldNotFindAutobuildCtor(T_MyService93#, [,])) {
			reg.serviceById("s93")			
		}
	}
	
	Void testThreadedServicesCanNotBeAutobuiltInCtor() {
		reg := threadScope { addModule(T_MyModule100#) }
		// by default, lets not mix up the scopes 'cos it's confusing
		// if they really want to, they can use registry.activeScope for resolution
		verifyIocErrMsg(ErrMsgs.autobuilder_couldNotFindAutobuildCtor(T_MyService93#, [,])) {
			reg.serviceById("s92")
		}
	}
}

@Js
internal const class T_MyModule85 {
	Void defineServices(RegistryBuilder defs) {
		defs.addService(T_MyService70#).withId("t70")
		defs.addService(T_MyService85#).withId("t85").withScopes(["thread"])
	}
	
	@Contribute { serviceType=T_MyService70# }
	Void contributeT70(Configuration config) {
		config.addPlaceholder("routes")
		config.set("key69", 69).before("routes")
	}
}

@Js
internal class T_MyService70 {
	new make(Int[] config) { }
}

@Js
internal const mixin T_MyService85 {
	abstract Str judge()
}
@Js
internal const class T_MyService85Impl : T_MyService85 {
	override Str judge() { "Dredd" }
}

@Js
internal const class T_MyModule98 {
	Void defineServices(RegistryBuilder defs) {
		defs.addService(T_MyService89#)		
		defs.addService(T_MyService89#).withId("PillowRoutes")
	}
}
@Js
internal const class T_MyService89 { }

@Js
internal const class T_MyModule100 {
	Void defineServices(RegistryBuilder defs) {
		defs.addService(T_MyService91#).withScopes(["thread"])
		defs.addService(T_MyService92#).withId("s92")
		defs.addService(T_MyService93#).withId("s93")
	}	
}
@Js
internal class T_MyService91 { }	// threaded
@Js
internal const class T_MyService92 {
	new make(Scope scope, |This|in) { 
		in(this)
		// T_MyService93 requires a threaded service
		scope.build(T_MyService93#)
	}
}
@Js
internal const class T_MyService93 {
	new make(T_MyService91 s91, |This|in) { } 	
}

@Js
internal const mixin T_MyService79 { }
@Js
internal const class T_MyService79Impl : T_MyService79 { }
