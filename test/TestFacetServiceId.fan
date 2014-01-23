
internal class TestFacetServiceId : IocTest {

	Void testFieldInjection() {
		reg := RegistryBuilder().addModule(T_MyModule53#).build.startup
		s33 := reg.dependencyByType(T_MyService33#) as T_MyService33
		verifyEq(s33->impl1->wotcha, "Go1")
		verifyEq(s33->impl2->wotcha, "Go2")
	}

	Void testConstCtorInjection() {
		reg := RegistryBuilder().addModule(T_MyModule53#).build.startup
		s35 := reg.dependencyByType(T_MyService35#) as T_MyService35 
		verifyEq(s35->impl1->wotcha, "Go1")
		verifyEq(s35->impl2->wotcha, "Go2")
	}

	Void testServiceTypeMustMatch() {
		reg := RegistryBuilder().addModule(T_MyModule53#).build.startup
		try {
			reg.dependencyByType(T_MyService34#)
			fail
		} catch (IocErr iocErr) {
			lin := iocErr.msg.split('\n')[0]
			msg := Regex<|afPlastic[0-9][0-9][0-9]|>.split(lin).join("XXX")
			verifyEq("Service Id 'impl1' of type XXX::T_MyService32Impl does not fit type ${T_MyService33?#.signature}", msg)
		}
	}
}

internal class T_MyModule53 {
	static Void bind(ServiceBinder binder) {
		binder.bind(PublicTestTypes.type("T_MyService32"), PublicTestTypes.type("T_MyService32Impl1")).withId("impl1")
		binder.bind(PublicTestTypes.type("T_MyService32"), PublicTestTypes.type("T_MyService32Impl2")).withId("impl2")
		binder.bind(T_MyService33#)
		binder.bind(T_MyService34#)
		binder.bind(T_MyService35#)
	}
}

internal class T_MyService33 {
	@Inject @ServiceId {id="impl1"}
	Obj? impl1
	@Inject @ServiceId {id="impl2"}
	Obj? impl2
}
internal class T_MyService35 {
	@Inject @ServiceId {id="impl1"}
	const Obj? impl1
	@Inject @ServiceId {id="impl2"}
	const Obj? impl2
	new make(|This|di) { di(this) }
}
internal class T_MyService34 {	
	@Inject @ServiceId {id="impl1"}
	T_MyService33? impl1
}
