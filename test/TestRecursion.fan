
class TestRecursion : IocTest {
	
	Void testErrOnRecursiveInjection1() {
		reg := RegistryBuilder().addModule(T_MyModule20#).build.startup
		verifyErrMsg(IocMessages.serviceRecursion(["s15", "s15"])) { 
			reg.serviceById("s15") 
		}
	}

	Void testErrOnRecursiveInjection2() {
		reg := RegistryBuilder().addModule(T_MyModule20#).build.startup
		verifyErrMsg(IocMessages.serviceRecursion(["s16", "s17", "s16"])) { 
			reg.serviceById("s16") 
		}
	}

	Void testErrOnRecursiveInjection3() {
		reg := RegistryBuilder().addModule(T_MyModule20#).build.startup
		verifyErrMsg(IocMessages.serviceRecursion(["s18", "s17", "s16", "s17"])) { 
			reg.serviceById("s18") 
		}
	}
	
}


internal class T_MyModule20 {
	static Void bind(ServiceBinder binder) {
		binder.bindImpl(T_MyService15#).withId("s15")
		binder.bindImpl(T_MyService16#).withId("s16")
		binder.bindImpl(T_MyService17#).withId("s17")
		binder.bindImpl(T_MyService18#).withId("s18")
	}
}

internal class T_MyService15 {
	@Inject
	T_MyService15? ser
}

internal class T_MyService16 {
	@Inject
	T_MyService17? ser
}

internal class T_MyService17 {
	@Inject
	T_MyService16 ser
	
	new make(|This|in) { in(this) }
}

internal class T_MyService18 {
	@Inject
	T_MyService17 ser
	
	new make(|This|in) { in(this) }
}

