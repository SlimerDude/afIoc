
abstract class IocTest : Test {
	
	Void verifyErrMsg(Str errMsg, |Obj| func) {
		errType := IocErr#
		try {
			func(4)
			throw Err("$errType not thrown")
		} catch (Err e) {
			if (!e.typeof.fits(errType)) 
				throw Err("Expected $errType got $e.typeof")
			if (e.msg != errMsg)
				throw Err("Expected: \n - $errMsg \nGot: \n - $e.msg")
		}
	}
}
