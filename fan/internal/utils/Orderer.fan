
** See http://en.wikipedia.org/wiki/Topological_sorting	
internal class Orderer {

	private Str:OrderedNode nodes	:= Str:OrderedNode[:] { caseInsensitive = true }

	Void addOrdered(Str id, Obj object, Str[] constraints := Str#.emptyList) {
		if (nodes.containsKey(id) && !nodes[id].isPlaceholder)
			throw IocErr(IocMessages.configKeyAlreadyAdded(id))
		getOrAdd(id, object)
		
		constraints.each |constraint| {
			valid := false
			eachId("before", constraint) |Str idName| {
				valid = true
				getOrAdd(idName)	// create placeholder
				node := getOrAdd(id)
				if (!node.dependsOn.contains(idName))
					node.dependsOn.add(idName)				
			}
			eachId("after", constraint) |Str idName| {
				valid = true
				node := getOrAdd(idName)
				if (!node.dependsOn.contains(id))
					node.dependsOn.add(id)
			}
			if (!valid)
				throw IocErr(IocMessages.configBadPrefix(constraint))
		}
	}

	OrderedNode[] order() {
		nodesIn	 := nodes.dup
		nodesOut := OrderedNode[,]
		
		while (!nodesIn.isEmpty) {
			ctx := OrderingCtx()
			ctx.withNode(nodesIn.vals[0]) |node| {
				visit(ctx, nodesIn, nodesOut, node)
			}
		}
		return nodesOut
	}
	
	internal Void eachId(Str prefix, Str constraint, |Str id| op) {
		constraint = constraint.trim.lower
		if (constraint.startsWith(prefix)) {
			idCsv := constraint[prefix.size..-1].trim
			if (idCsv.startsWith(":") || idCsv.startsWith("-"))
				idCsv = idCsv[1..-1].trim
			idNames := idCsv.split(',', true)
			idNames.each {
				if (!it.isEmpty)
					op.call(it)
			}
		}
	}

	private Void visit(OrderingCtx ctx, Str:OrderedNode nodesIn, OrderedNode[] nodesOut, OrderedNode n) {
		// follow the dependencies until we find a node that depends on no-one
		nodesIn
			.findAll { 
				it.dependsOn.any |depName| { 
					depName == n.name  
				}
			}
			.each { 
				ctx.withNode(it) |node| { 
					visit(ctx, nodesIn, nodesOut, node)
				}
			}
		nodesIn.remove(n.name)
		nodesOut.add(n)
	}	

	private OrderedNode getOrAdd(Str name, Obj? payload := null) {
		node := nodes.getOrAdd(name) {			
			OrderedNode(name, payload)
		}
		if (payload != null)
			node.payload = payload
		return node
	}
}

internal class OrderedNode {
	Str 	name
	Str[] 	dependsOn	:= [,]
	Obj? 	payload	
	
	new make(Str name, Obj? payload := null) {
		this.name 	 = name
		this.payload = payload
	}
	
	Bool isPlaceholder() {
		payload == null
	}
	
	override Str toStr() {
		"OrderedNode:$name->" + dependsOn.join(",")
	}
}

internal class OrderingCtx {
	private OrderedNode[]	nodeStack	:= [,]
	
	Void withNode(OrderedNode node, |OrderedNode node| operation) {
		nodeStack.push(node)

		// check for recursion
		nodeStack[0..<-1].each { 
			if (it == node)
				throw IocErr(IocMessages.configRecursion(stackNames))
		}
		
		if (node.isPlaceholder)
			throw IocErr(IocMessages.configIsPlaceholder(node.name))

		try {
			operation.call(node)
		} finally {			
			nodeStack.pop
		}
	}
	
	Str[] stackNames() {
		nodeStack.map { it.name }
	}
	
	override Str toStr() {
		stackNames.join(" -> ")
	}
}
