
internal class TestRegistryMethods : IocTest {

	Void testServiceById() {
		reg := RegistryBuilder().addModule(T_MyModule01#).build.startup
		T_MyService01 myService1 := reg.serviceById("t_myservice01")
		verifyEq(myService1.service.kick, "ASS!")
		verifySame(myService1, reg.serviceById("t_MyService01"))
	}

	Void testDependencyByType() {
		reg := RegistryBuilder().addModule(T_MyModule01#).build.startup
		T_MyService01 myService1 := reg.dependencyByType(T_MyService01#)
		verifyEq(myService1.service.kick, "ASS!")
		verifySame(myService1, reg.dependencyByType(T_MyService01#))
	}

	Void testAutobuild() {
		reg := RegistryBuilder().addModule(T_MyModule01#).build.startup
		T_MyService01 myService1 := reg.autobuild(T_MyService01#)
		verifyEq(myService1.service.kick, "ASS!")
		verifyNotSame(myService1, reg.autobuild(T_MyService01#))
	}
	
	Void testInjectIntoFields() {
		reg := RegistryBuilder().addModule(T_MyModule01#).build.startup
		T_MyService01 myService1 := T_MyService01()
		verifyNull(myService1.service)
		reg.injectIntoFields(myService1)
		verifyEq(myService1.service.kick, "ASS!")
	}
}

internal class T_MyModule01 {
	static Void bind(ServiceBinder binder) {
		binder.bind(T_MyService01#)
		binder.bind(T_MyService02#)
	}
}

internal class T_MyService01 {
	@Inject
	T_MyService02? service
}

internal class T_MyService02 {
	Str kick	:= "ASS!"
}