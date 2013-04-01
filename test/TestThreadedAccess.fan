using concurrent

class TestThreadedAccess : Test {
	
	Void testAppVsThread() {
		Registry reg := RegistryBuilder().addModule(T_MyModule16#).build.startup
		
		app1 := reg.serviceById("app")
		the1 := reg.serviceById("the")

		Actor(ActorPool()) |->| {
			app2 := reg.serviceById("app")
			assertSame(app1, app2)
			
			the2 := reg.serviceById("the")
			assertNotSame(the1, the2)
		}.send(null).get

		Actor(ActorPool()) |->| {
			app2 := reg.serviceById("app")
			assertSame(app1, app2)
			
			the2 := reg.serviceById("the")
			assertNotSame(the1, the2)
		}.send(null).get
	}

	Void testThreadInApp() {
		Registry reg := RegistryBuilder().addModule(T_MyModule17#).build.startup

		// can not inject a perThread service into a perApp service
		verifyErr(IocErr#) {
			s12 := reg.serviceById("s12")	// perThread
			s13 := reg.serviceById("s13")	// perApp
		}		

//		Actor(ActorPool()) |->| {
//			s12i := reg.serviceById("s12")
//			assertNotSame(s12, s12i)
//
//			s13i := reg.serviceById("s13")
//			assertSame(s13, s13i)
//
//			// TODO: Think about having a PerThread wrapper Injection Provider : PerThread.get
//			assertNotSame(s13->s12, s13i->s12)
//
//		}.send(null).get
		
		// thread in apps, not allowed
		verifyErr(IocErr#) { reg.serviceById("s14") }
	}

	Void testAppInThread() {
		Registry reg := RegistryBuilder().addModule(T_MyModule18#).build.startup

		s12 := reg.serviceById("s12")	// perApp
		s13 := reg.serviceById("s13")	// perThread

		Actor(ActorPool()) |->| {
			s12i := reg.serviceById("s12")
			assertSame(s12, s12i)

			s13i := reg.serviceById("s13")
			assertNotSame(s13, s13i)

			assertSame(s13->s12, s13i->s12)
			
		}.send(null).get
	}

	Void testErrThrownWhenConstFieldNotSet() {
		Registry reg := RegistryBuilder().addModule(T_MyModule19#).build.startup
		verifyErr(IocErr#) { reg.serviceById("s14") }
	}

	static Void assertSame(Obj? o1, Obj? o2) {
		if (o1 !== o2)
			throw Err("Are NOT the same - $o1 : $o2")
	}

	static Void assertNotSame(Obj? o1, Obj? o2) {
		if (o1 === o2)
			throw Err("ARE the same - $o1 : $o2")
	}
}

internal class T_MyModule16 {
	static Void bind(ServiceBinder binder) {
		binder.bindImpl(T_MyService12#).withId("app").withScope(ServiceScope.perApplication)
		binder.bindImpl(T_MyService12#).withId("the").withScope(ServiceScope.perThread)
	}
}

internal class T_MyModule17 {
	static Void bind(ServiceBinder binder) {
		binder.bindImpl(T_MyService12#).withId("s12").withScope(ServiceScope.perThread)
		binder.bindImpl(T_MyService13#).withId("s13").withScope(ServiceScope.perApplication)
		binder.bindImpl(T_MyService13#).withId("s14").withScope(ServiceScope.perApplication)
	}
}

internal class T_MyModule18 {
	static Void bind(ServiceBinder binder) {
		binder.bindImpl(T_MyService12#).withId("s12").withScope(ServiceScope.perApplication)
		binder.bindImpl(T_MyService13#).withId("s13").withScope(ServiceScope.perThread)
	}
}

internal class T_MyModule19 {
	static Void bind(ServiceBinder binder) {
		binder.bindImpl(T_MyService14#).withId("s14")
	}
}

internal const class T_MyService12 {
	const Str kick	:= "DREDD"
}

internal const class T_MyService13 {
	const T_MyService12 s12
	
//	new make(|This|in) { in(this) }
	new make(T_MyService12 s12) { this.s12 = s12 }
}

internal class T_MyService14 {
	@Inject
	const T_MyService12? s12	
}
