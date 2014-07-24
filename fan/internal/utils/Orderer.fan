
//L ← Empty list that will contain the sorted nodes
//while there are unmarked nodes do
//    select an unmarked node n
//    visit(n) 
//function visit(node n)
//    if n has a temporary mark then stop (not a DAG)
//    if n is not marked (i.e. has not been visited yet) then
//        mark n temporarily
//        for each node m with an edge from n to m do
//            visit(m)
//        mark n permanently
//        add n to L
** 
** @see `http://en.wikipedia.org/wiki/Topological_sorting`	
internal class Orderer {

	internal static const Str placeholder	:= "AFIOC-PLACEHOLDER"
	internal static const Str delete		:= "AFIOC-DELETE"
	internal static const Str NULL			:= "AFIOC-NULL"
	private Str:OrderedNode nodes			:= Str:OrderedNode[:] { ordered = true }

	Void addPlaceholder(Str id, Str? constraints := null) {
		addOrdered(id, placeholder, constraints)
	}

	Void remove(Str id) {
		addOrdered(id, delete)
	}

	Void addOrdered(Str origId, Obj? object, Str? constraints := null) {
		id := origId.lower	// because our map is ordered (for easy testing)
		if (nodes.containsKey(id) && !nodes[id].isPlaceholder)
			throw IocErr(IocMessages.configKeyAlreadyAdded(origId))
		getOrAdd(id, object ?: NULL)

		constraints = (constraints?.trim?.isEmpty ?: true) ? null : constraints
		constraints?.split(',', true)?.each |constraint| {
			valid := false
			eachConstraint("before", constraint) |Str idName| {
				valid = true
				getOrAdd(idName)	// create placeholder
				node := getOrAdd(id)
				if (!node.isBefore.contains(idName))
					node.isBefore.add(idName)				
			}
			eachConstraint("after", constraint) |Str idName| {
				valid = true
				node := getOrAdd(idName)
				if (!node.isBefore.contains(id))
					node.isBefore.add(id)
			}
			if (!valid)
				throw IocErr(IocMessages.configBadPrefix(constraints))
		}
	}

	Obj?[] toOrderedList() {
		order().exclude { it.payload === placeholder || it.payload === delete }.map { it.payload === NULL ? null : it.payload }
	}

	Void clear() {
		nodes.each { it.payload = null }
		nodes.clear
	}

	internal OrderedNode[] order() {
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

	internal Void eachConstraint(Str prefix, Str? constraint, |Str id| op) {
		if (constraint.lower.startsWith(prefix.lower)) {
			id := constraint[prefix.size..-1].trim
			if (id.startsWith(":") || id.startsWith("-"))
				id = id[1..-1].trim
			if (!id.isEmpty)
				op.call(id.lower)
		}
	}

	private Void visit(OrderingCtx ctx, Str:OrderedNode nodesIn, OrderedNode[] nodesOut, OrderedNode n) {
		// follow the dependencies until we find a node that depends on no-one
		nodesIn
			.findAll { 
				it.isBefore.any |depName| { 
					// BugFix 1.3.6: we sometimes lower the case of the isBefore ids 
					// they should be case-insensitive anyway
					depName.equalsIgnoreCase(n.name)
				}
			}
			.each { 
				ctx.withNode(it) |node| {
					// BugFix 1.3.10: ensure we don't visit nodes that have already been moved to nodeOut 
					if (nodesIn.containsKey(node.name))
						visit(ctx, nodesIn, nodesOut, node)
				}
			}

		// move node from nodesIn to nodesOut
		nodesIn.remove(n.name)
		nodesOut.add(n)
	}	

	private OrderedNode getOrAdd(Str name, Obj? payload := null) {
		node := nodes.getOrAdd(name) |->Obj| {			
			return OrderedNode(name, payload)
		}
		if (payload != null)
			node.payload = payload
		return node
	}
}

internal class OrderedNode {
	Str 	name
	Str[] 	isBefore	:= [,]
	Obj? 	payload	

	new make(Str name, Obj? payload := null) {
		this.name 	 = name
		this.payload = payload
	}

	Bool isPlaceholder() {
		payload == null
	}

	override Str toStr() {
		"${name}->(" + isBefore.join(",") + ")"
	}
}

internal class OrderingCtx {
	private OrderedNode[]	nodeStack	:= [,]

	Void withNode(OrderedNode node, |OrderedNode node| operation) {
		nodeStack.push(node)

		// check for recursion
		nodeStack.eachRange(0..<-1) { 
			if (it == node)
				throw IocErr(IocMessages.configRecursion(stackNames))
		}

		if (node.isPlaceholder) {
			Env.cur.err.printLine(nodeStack)
			throw IocErr(IocMessages.configIsPlaceholder(node.name))
		}

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

