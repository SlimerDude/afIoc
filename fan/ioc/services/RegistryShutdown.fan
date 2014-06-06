using concurrent::Future
using afConcurrent::SynchronizedState

@NoDoc @Deprecated { msg="Use RegistryShutdown instead" }
const mixin RegistryShutdownHub {
	abstract Void addRegistryShutdownListener(Str id, Str[] constraints, |->| listener)
	abstract Void addRegistryWillShutdownListener(Str id, Str[] constraints, |->| listener)
}

** (Service) - Contribute functions to be executed on `Registry` shutdown. 
** All functions need to be immutable, which essentially means they can only reference 'const' classes.
** Example usage:
** 
** pre>
** class AppModule {
**     @Contribute { serviceType=RegistryShutdown# }
**     static Void contributeRegistryShutdown(OrderedConfig conf, MyService myService) {
**         conf.add |->| { myService.shutdown() }
**     }
** }
** <pre
** 
** If the shutdown method of your service depends on other services being available, add a constraint on 'IocShutdown': 
** 
**   conf.addOrdered("MyServiceShutdown", |->| { myService.shutdown() }, ["BEFORE: IocShutdown"])
** 
** Note that Errs thrown by shutdown functions will be logged and then swallowed.
** 
** @uses OrderedConfig of |->|
const mixin RegistryShutdown : RegistryShutdownHub {
	internal abstract Void shutdown()
}

internal const class RegistryShutdownImpl : RegistryShutdown {
	private const static Log 		log 		:= Utils.getLog(RegistryShutdown#)
	private const OneShotLock 		lock		:= OneShotLock(IocMessages.registryShutdown)
	private const SynchronizedState	conState
	private const |->|[] 			shutdownFuncs
 
	new make(|->|[] shutdownFuncs,  ActorPools actorPools) {
		this.shutdownFuncs = shutdownFuncs
		conState = SynchronizedState(actorPools[IocConstants.systemActorPool], RegistryShutdownHubState#)
	}
	
	override Void shutdown() {
		lock.check
		lock.lock

		registryWillShutdown
		
		shutdownFuncs.each | |->| listener| {
			try {
				listener.call
			} catch (Err e) {
				log.err(IocMessages.shutdownListenerError(listener, e))
			}
		}
		
		registryHasShutdown
	}
	
	override Void addRegistryShutdownListener(Str id, Str[] constraints, |->| listener) {
		lock.check
		iHandler := listener.toImmutable
		conState.withState |RegistryShutdownHubState state| {
			state.listeners.addOrdered(id, iHandler, constraints)
		}.get
	}

	override Void addRegistryWillShutdownListener(Str id, Str[] constraints, |->| listener) {
		lock.check
		iHandler := listener.toImmutable
		conState.withState |RegistryShutdownHubState state| {
			state.preListeners.addOrdered(id, iHandler, constraints)
		}.get
	}

	private Void registryWillShutdown() {
		preListeners.each | |->| listener| {
			try {
				listener.call
			} catch (Err e) {
				log.err(IocMessages.shutdownListenerError(listener, e))
			}
		}
		conState.withState |RegistryShutdownHubState state| { state.preListeners.clear }
	}

	private Void registryHasShutdown() {
		listeners.each |listener| {
			try {
				listener()
			} catch (Err e) {
				log.err(IocMessages.shutdownListenerError(listener, e))
			}
		}
		conState.withState |RegistryShutdownHubState state| { state.listeners.clear }
	}
	
	private |->|[] preListeners() {
		conState.getState |RegistryShutdownHubState state -> Obj| { state.preListeners.toOrderedList.toImmutable }
	}

	private |->|[] listeners() {
		conState.getState |RegistryShutdownHubState state -> Obj| { state.listeners.toOrderedList.toImmutable }
	}
}

internal class RegistryShutdownHubState {
	Orderer preListeners	:= Orderer()
	Orderer listeners		:= Orderer()
}