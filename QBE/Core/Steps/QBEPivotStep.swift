import Foundation

private func toDictionary<E, K, V>(array: [E], transformer: (element: E) -> (key: K, value: V)?) -> Dictionary<K, V> {
	return array.reduce([:]) { (var dict, e) in
		if let (key, value) = transformer(element: e) {
			dict[key] = value
		}
		return dict
	}
}

class QBEPivotStep: QBEStep {
	var rows: [QBEColumn] = []
	var columns: [QBEColumn] = []
	var aggregates: [QBEAggregation] = []
	
	override init(previous: QBEStep?) {
		super.init(previous: previous)
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		
		aggregates = (aDecoder.decodeObjectForKey("aggregates") as? [QBEAggregation]) ?? []
		
		if let r = aDecoder.decodeObjectForKey("rows") as? [String] {
			rows = r.map({QBEColumn($0)})
		}
		
		if let c = aDecoder.decodeObjectForKey("columns") as? [String] {
			columns = c.map({QBEColumn($0)})
		}
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		fixupColumnNames()
		
		// NSCoder can't store QBEColumn, so we store the raw names
		let c = columns.map({$0.name})
		let r = rows.map({$0.name})
		
		coder.encodeObject(r, forKey: "rows")
		coder.encodeObject(c, forKey: "columns")
		coder.encodeObject(aggregates, forKey: "aggregates")
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if !short && aggregates.count == 1 {
			let aggregation = aggregates[0]
			if rows.count != 1 || columns.count != 0 {
				return String(format: NSLocalizedString("Pivot: %@ of %@", comment: "Pivot with 1 aggregate"),
					aggregation.reduce.explain(locale),
					aggregation.map.explain(locale))
			}
			else {
				let row = rows[0]
				return String(format: NSLocalizedString("Pivot: %@ of %@ grouped by %@", comment: "Pivot with 1 aggregate"),
					aggregation.reduce.explain(locale),
					aggregation.map.explain(locale),
					row.name)
			}
		}
		
		return NSLocalizedString("Pivot data", comment: "")
	}
	
	private func fixupColumnNames() {
		var columnNames = Set(rows)
		
		// Make sure we don't create duplicate columns
		for idx in 0..<columns.count {
			let column = columns[idx]
			if columnNames.contains(column) {
				columns[idx] = column.newName({return !columnNames.contains($0)})
			}
		}
		
		columnNames.unionInPlace(Set(columns))
		
		for idx in 0..<aggregates.count {
			let aggregation = aggregates[idx]
			
			if columnNames.contains(aggregation.targetColumnName) {
				aggregation.targetColumnName = aggregation.targetColumnName.newName({return !columnNames.contains($0)})
			}
		}
	}
	
	override func apply(data: QBEFallible<QBEData>, job: QBEJob?, callback: (QBEFallible<QBEData>) -> ()) {
		fixupColumnNames()
		var rowGroups = toDictionary(rows, { ($0, QBESiblingExpression(columnName: $0) as QBEExpression) })
		let colGroups = toDictionary(columns, { ($0, QBESiblingExpression(columnName: $0) as QBEExpression) })
		for (k, v) in colGroups {
			rowGroups[k] = v
		}
		
		let values = toDictionary(aggregates, { ($0.targetColumnName, $0) })
		let resultData = data.use({$0.aggregate(rowGroups, values: values)})
		if columns.count == 0 {
			callback(resultData)
		}
		else {
			let pivotedData = resultData.use({$0.pivot(columns, vertical: rows, values: aggregates.map({$0.targetColumnName}))})
			callback(pivotedData)
		}
	}
	
	class func suggest(aggregateRows: NSIndexSet, columns aggregateColumns: Set<QBEColumn>, inRaster raster: QBERaster, fromStep: QBEStep?) -> [QBEStep] {
		if aggregateColumns.count == 0 {
			return []
		}
		
		// Check to see if the selected rows have similar values for other than the relevant columns
		let groupColumnCandidates = Set<QBEColumn>(raster.columnNames).subtract(aggregateColumns)
		let sameValues = aggregateRows.count > 1 ? raster.commonalitiesOf(aggregateRows, inColumns: groupColumnCandidates) : [:]
		
		// What are our aggregate functions? Select the most likely ones (user can always change)
		let aggregateFunctions = [QBEFunction.Sum, QBEFunction.Count, QBEFunction.Average]
		
		// Generate a suggestion for each type of aggregation we have
		var suggestions: [QBEStep] = []
		for fun in aggregateFunctions {
			let step = QBEPivotStep(previous: fromStep)
			
			for column in aggregateColumns {
				step.aggregates.append(QBEAggregation(map: QBESiblingExpression(columnName: column), reduce: fun, targetColumnName: column))
			}
			
			for (sameColumn, sameValue) in sameValues {
				step.rows.append(sameColumn)
			}
			
			suggestions.append(step)
		}
		
		return suggestions
	}
}