import Foundation

class QBEFlattenStep: QBEStep {
	var colColumn: QBEColumn?
	var rowColumn: QBEColumn?
	var valueColumn: QBEColumn
	var rowIdentifier: QBEExpression?
	
	override init(previous: QBEStep?) {
		self.colColumn = QBEColumn(NSLocalizedString("Column", comment: ""))
		self.rowColumn = QBEColumn(NSLocalizedString("Row", comment: ""))
		self.valueColumn = QBEColumn(NSLocalizedString("Value", comment: ""))
		super.init(previous: previous)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		return NSLocalizedString("Make columnar", comment: "Short explanation of QBEFlattenStep")
	}
	
	required init(coder aDecoder: NSCoder) {
		if let cc = aDecoder.decodeObjectForKey("colColumn") as? String {
			colColumn = QBEColumn(cc)
		}
		
		if let rc = aDecoder.decodeObjectForKey("rowColumn") as? String {
			rowColumn = QBEColumn(rc)
		}
		
		valueColumn = QBEColumn((aDecoder.decodeObjectForKey("valueColumn") as? String) ?? "")
		rowIdentifier = aDecoder.decodeObjectForKey("rowIdentifier") as? QBEExpression
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(colColumn?.name, forKey: "colColumn")
		coder.encodeObject(rowColumn?.name, forKey: "rowColumn")
		coder.encodeObject(valueColumn.name, forKey: "valueColumn")
		coder.encodeObject(rowIdentifier, forKey: "rowIdentifier")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEFallible<QBEData>, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		/* If a column is set to put a row identifier in, but there is no expression, fill in an expression that uses the
		value in the first column. */
		if rowIdentifier == nil && rowColumn != nil {
			switch data {
				case .Success(let d):
					d.value.columnNames(job) { (columns) -> () in
						if let firstColumn = columns.first {
							let ri = QBESiblingExpression(columnName: firstColumn)
							callback(QBEFallible(d.value.flatten(self.valueColumn, columnNameTo: self.colColumn, rowIdentifier: ri, to: self.rowColumn)))
						}
						else {
							callback(.Failure(NSLocalizedString("The data set that is to be flattened contained no rows.", comment: "")))
						}
					}
				
				case .Failure(_):
					callback(data)
			}
		}
		else {
			callback(data.use({$0.flatten(valueColumn, columnNameTo: colColumn, rowIdentifier: rowIdentifier, to: rowColumn)}))
		}
	}
}