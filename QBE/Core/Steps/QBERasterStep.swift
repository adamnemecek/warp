import Foundation

class QBERasterStep: QBEStep {
	let raster: QBERaster
	let staticExampleData: QBERasterData
	let staticFullData: QBEData
	
	init(raster: QBERaster) {
		self.raster = raster
		self.staticExampleData = QBERasterData(raster: raster)
		self.staticFullData = staticExampleData
		super.init(previous: nil)
	}
	
	required init(coder aDecoder: NSCoder) {
		self.raster = (aDecoder.decodeObjectForKey("raster") as? QBERaster) ?? QBERaster()
		staticExampleData = QBERasterData(raster: self.raster)
		staticFullData = staticExampleData
		super.init(coder: aDecoder)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		return NSLocalizedString("Data table", comment: "")
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(raster, forKey: "raster")
		super.encodeWithCoder(coder)
	}
	
	override func fullData(job: QBEJob?, callback: (QBEData) -> ()) {
		callback(staticFullData)
	}
	
	override func exampleData(job: QBEJob?, maxInputRows: Int, maxOutputRows: Int, callback: (QBEData) -> ()) {
		callback(staticExampleData.limit(min(maxInputRows, maxOutputRows)))
	}
}