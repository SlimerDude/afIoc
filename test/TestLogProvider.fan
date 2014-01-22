
internal class TestLogProvider : IocTest {
	
	Void testLogger() {
		reg := RegistryBuilder().addModule(T_MyModule97#).build.startup
		s86 := (T_MyService86) reg.serviceById("s86")
		s86.log.info("Yo!")
	}

	Void testLoggerFuncCanChange() {
		reg := RegistryBuilder().addModule(T_MyModule97#).build.startup
		lp  := (LogProvider) reg.dependencyByType(LogProvider#)
		lp.logCreatorFunc = |Type t->Log| { Log.get(t.name) }
		s86 := (T_MyService86) reg.serviceById("s86")
		s86.log.info("Yo!")
	}
}

internal class T_MyModule97 {
	static Void bind(ServiceBinder binder) {
		binder.bind(T_MyService86#).withId("s86")
	}
}

internal class T_MyService86 {
	@Inject 
	Log? log
}
