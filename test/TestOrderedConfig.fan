
class TestOrderedConfig : IocTest {
	
	Void testErrIfConfigIsGeneric() {
		reg := RegistryBuilder().addModule(T_MyModule31#).build.startup
		verifyErrMsg(IocMessages.orderedConfigTypeIsGeneric(List#, "s20")) {
			reg.serviceById("s20")
		}
	}

	Void testBasicConfig() {
		reg := RegistryBuilder().addModule(T_MyModule30#).build.startup
		s19 := reg.serviceById("s19") as T_MyService19
		verifyEq(s19.config, Str["wot", "ever"])
	}

	Void testBasicConfigViaBuilder() {
		Utils.setLoglevelDebug
		reg := RegistryBuilder().addModule(T_MyModule32#).build.startup
		s21 := reg.serviceById("s21") as T_MyService21
		verifyEq(s21.config, Str["wot", "ever", "ASS!"])
	}

	Void testConfigMethodInjection() {
		Utils.setLoglevelDebug
		reg := RegistryBuilder().addModule(T_MyModule33#).build.startup
		s21 := reg.serviceById("s21") as T_MyService21
		verifyEq(s21.config, Str["wot", "ASS!"])
	}

}



internal class T_MyModule30 {
	static Void bind(ServiceBinder binder) {
		binder.bindImpl(T_MyService19#).withId("s19")
	}
	
	@Contribute{ serviceId="s19" }
	static Void cont(OrderedConfig config) {
		config.addUnordered("wot")
	}
	@Contribute{ serviceId="s19" }
	static Void cont2(OrderedConfig config) {
		config.addUnordered("ever")
	}
}

internal class T_MyService19 {
	Str[] config
	new make(Str[] config) {
		this.config = config
	}
}

internal class T_MyModule31 {
	static Void bind(ServiceBinder binder) {
		binder.bindImpl(T_MyService20#).withId("s20")
	}
	
	@Contribute{ serviceId="s20" }
	static Void cont(OrderedConfig config) {
		config.addUnordered("wot")
	}
}

internal class T_MyService20 {
	new make(List config) { }
}

internal class T_MyModule32 {
	static Void bind(ServiceBinder binder) {
		binder.bindImpl(T_MyService2#).withId("s2")
	}
	
	@Build
	static T_MyService21 buildS21(Str[] str, T_MyService2 s2) {
		T_MyService21(str.add(s2.kick))
	}
	
	@Contribute{ serviceId="s21" }
	static Void cont(OrderedConfig config) {
		config.addUnordered("wot")
	}
	@Contribute{ serviceId="s21" }
	static Void cont2(OrderedConfig config) {
		config.addUnordered("ever")
	}
}

internal class T_MyService21 {
	Str[] config
	new make(Str[] config) {
		this.config = config
	}
}

internal class T_MyModule33 {
	static Void bind(ServiceBinder binder) {
		binder.bindImpl(T_MyService2#).withId("s2")
		binder.bindImpl(T_MyService21#).withId("s21")
	}
	
	@Contribute{ serviceId="s21" }
	static Void cont(OrderedConfig config, T_MyService2 s2) {
		config.addUnordered("wot")
		config.addUnordered(s2.kick)
	}
}
