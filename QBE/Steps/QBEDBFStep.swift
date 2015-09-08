import Foundation
import WarpCore

final class QBEDBFStream: NSObject, QBEStream {
	let url: NSURL

	private var queue = dispatch_queue_create("nl.pixelspark.Warp.QBEDBFStream", DISPATCH_QUEUE_SERIAL)
	private let handle: DBFHandle
	private let recordCount: Int32
	private let fieldCount: Int32
	private var columns: [QBEColumn]? = nil
	private var types: [DBFFieldType]? = nil
	private var position: Int32 = 0

	init(url: NSURL) {
		self.url = url
		self.handle = DBFOpen(url.fileSystemRepresentation, "rb")
		self.recordCount = DBFGetRecordCount(self.handle)
		self.fieldCount = DBFGetFieldCount(self.handle)
	}

	deinit {
		DBFClose(handle)
	}

	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		if self.columns == nil {
			let fieldCount = DBFGetFieldCount(handle)
			var fields: [QBEColumn] = []
			var types: [DBFFieldType] = []
			for i in 0..<fieldCount {
				var fieldName =  [CChar](count: 12, repeatedValue: 0)
				let type = DBFGetFieldInfo(handle, i, &fieldName, nil, nil)
				if let fieldNameString = String(CString: fieldName, encoding: NSUTF8StringEncoding) {
					fields.append(QBEColumn(fieldNameString))
					types.append(type)
				}
			}
			self.types = types
			columns = fields
		}

		callback(.Success(columns!))
	}

	func fetch(job: QBEJob, consumer: QBESink) {
		dispatch_async(self.queue) {
			self.columnNames(job) { (columnNames) -> () in
				let end = min(self.recordCount-1, self.position + QBEStreamDefaultBatchSize - 1)

				var rows: [QBETuple] = []
				for recordIndex in self.position...end {
					if DBFIsRecordDeleted(self.handle, recordIndex) == 0 {
						var row: QBETuple = []
						for fieldIndex in 0..<self.fieldCount {
							if DBFIsAttributeNULL(self.handle, recordIndex, fieldIndex) != 0 {
								row.append(QBEValue.EmptyValue)
							}
							else {
								switch self.types![Int(fieldIndex)].rawValue {
									case FTString.rawValue:
										if let s = String(CString: DBFReadStringAttribute(self.handle, recordIndex, fieldIndex), encoding: NSUTF8StringEncoding) {
											row.append(QBEValue.StringValue(s))
										}
										else {
											row.append(QBEValue.InvalidValue)
										}

									case FTInteger.rawValue:
										row.append(QBEValue.IntValue(Int(DBFReadIntegerAttribute(self.handle, recordIndex, fieldIndex))))

									case FTDouble.rawValue:
										row.append(QBEValue.DoubleValue(DBFReadDoubleAttribute(self.handle, recordIndex, fieldIndex)))

									case FTInvalid.rawValue:
										row.append(QBEValue.InvalidValue)

									case FTLogical.rawValue:
										// TODO: this needs to be translated to a BoolValue. However, no idea how logical values are stored in DBF..
										row.append(QBEValue.InvalidValue)

									default:
										row.append(QBEValue.InvalidValue)
								}
							}
						}

						rows.append(row)
					}
				}

				self.position = end
				job.async {
					consumer(.Success(Array(rows)), self.position < (self.recordCount-1))
				}
			}
		}
	}

	func clone() -> QBEStream {
		return QBEDBFStream(url: self.url)
	}
}

class QBEDBFWriter: NSObject, NSCoding, QBEFileWriter {
	class func explain(fileExtension: String, locale: QBELocale) -> String {
		return NSLocalizedString("dBase III", comment: "")
	}

	class var fileTypes: Set<String> { get {
		return Set<String>(["dbf"])
	} }

	required init(locale: QBELocale, title: String?) {
	}

	func encodeWithCoder(aCoder: NSCoder) {
	}

	required init?(coder aDecoder: NSCoder) {
	}

	func writeData(data: QBEData, toFile file: NSURL, locale: QBELocale, job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
		let stream = data.stream()

		let handle = DBFCreate(file.fileSystemRepresentation)
		var rowIndex = 0

		// Write column headers
		stream.columnNames(job) { (columnNames) -> () in
			switch columnNames {
			case .Success(let cns):
				var fieldIndex = 0
				for col in cns {
					// make field
					if let name = col.name.cStringUsingEncoding(NSUTF8StringEncoding) {
						DBFAddField(handle, name, FTString, 255, 0)
					}
					else {
						let name = "COL\(fieldIndex)"
						DBFAddField(handle, name.cStringUsingEncoding(NSUTF8StringEncoding)!, FTString, 255, 0)
					}
					fieldIndex++
				}

				var cb: QBESink? = nil
				cb = { (rows: QBEFallible<Array<QBETuple>>, hasNext: Bool) -> () in
					switch rows {
					case .Success(let rs):
						// We want the next row, so fetch it while we start writing this one.
						if hasNext {
							job.async {
								stream.fetch(job, consumer: cb!)
							}
						}

						job.time("Write CSV", items: rs.count, itemType: "rows") {
							for row in rs {
								var cellIndex = 0
								for cell in row {
									if let s = cell.stringValue?.cStringUsingEncoding(NSUTF8StringEncoding) {
										DBFWriteStringAttribute(handle, Int32(rowIndex), Int32(cellIndex), s)
									}
									else {
										DBFWriteNULLAttribute(handle, Int32(rowIndex), Int32(cellIndex))
									}
									// write field
									cellIndex++
								}
								rowIndex++
							}
						}

						if !hasNext {
							DBFClose(handle)
							callback(.Success())
						}

					case .Failure(let e):
						callback(.Failure(e))
					}
				}

				stream.fetch(job, consumer: cb!)

			case .Failure(let e):
				callback(.Failure(e))
			}
		}
	}

	func sentence(locale: QBELocale) -> QBESentence? {
		return nil
	}
}

class QBEDBFSourceStep: QBEStep {
	var file: QBEFileReference?

	init(url: NSURL) {
		self.file = QBEFileReference.URL(url)
		super.init(previous: nil)
	}

	required init(coder aDecoder: NSCoder) {
		let d = aDecoder.decodeObjectForKey("fileBookmark") as? NSData
		let u = aDecoder.decodeObjectForKey("fileURL") as? NSURL
		self.file = QBEFileReference.create(u, d)
		super.init(coder: aDecoder)
	}

	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}

	private func sourceData() -> QBEFallible<QBEData> {
		if let url = file?.url {
			let s = QBEDBFStream(url: url)
			return .Success(QBEStreamData(source: s))
		}
		else {
			return .Failure(NSLocalizedString("The location of the DBF source file is invalid.", comment: ""))
		}
	}

	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		callback(sourceData())
	}

	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		callback(sourceData().use({ d in return d.limit(maxInputRows) }))
	}

	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(self.file?.url, forKey: "fileURL")
		coder.encodeObject(self.file?.bookmark, forKey: "fileBookmark")
	}

	override func sentence(locale: QBELocale) -> QBESentence {
		let fileTypes = [
			"dbf"
		]

		return QBESentence(format: NSLocalizedString("Read DBF file [#]", comment: ""),
			QBESentenceFile(file: self.file, allowedFileTypes: fileTypes, callback: { [weak self] (newFile) -> () in
				self?.file = newFile
			})
		)
	}

	override func willSaveToDocument(atURL: NSURL) {
		self.file = self.file?.bookmark(atURL)
	}

	override func didLoadFromDocument(atURL: NSURL) {
		self.file = self.file?.resolve(atURL)
		self.file?.url?.startAccessingSecurityScopedResource()
	}
}