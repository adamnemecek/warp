import Foundation
import WarpCore

class QBEFactory {
	typealias QBEStepViewCreator = (step: QBEStep?, delegate: QBESuggestionsViewDelegate) -> NSViewController?
	typealias QBEFileReaderCreator = (url: NSURL) -> QBEStep?
	
	static let sharedInstance = QBEFactory()
	
	let fileWriters: [QBEFileWriter.Type] = [
		QBECSVWriter.self,
		QBEXMLWriter.self,
		QBEHTMLWriter.self,
		QBEDBFWriter.self,
		QBESQLiteWriter.self
	]
	
	private let fileReaders: [String: QBEFileReaderCreator] = [
		"public.comma-separated-values-text": {(url) in return QBECSVSourceStep(url: url)},
		"csv": {(url) in return QBECSVSourceStep(url: url)},
		"tsv": {(url) in return QBECSVSourceStep(url: url)},
		"txt": {(url) in return QBECSVSourceStep(url: url)},
		"tab": {(url) in return QBECSVSourceStep(url: url)},
		"public.delimited-values-text": {(url) in return QBECSVSourceStep(url: url)},
		"public.tab-separated-values-text": {(url) in return QBECSVSourceStep(url: url)},
		"public.text": {(url) in return QBECSVSourceStep(url: url)},
		"public.plain-text": {(url) in return QBECSVSourceStep(url: url)},
		"org.sqlite.v3": {(url) in return QBESQLiteSourceStep(url: url)},
		"sqlite": {(url) in return QBESQLiteSourceStep(url: url)},
		"dbf": {(url) in return QBEDBFSourceStep(url: url)}
	]
	
	private let stepViews: Dictionary<String, QBEStepViewCreator> = [
		QBECalculateStep.className(): {QBECalculateStepView(step: $0, delegate: $1)},
		QBEPivotStep.className(): {QBEPivotStepView(step: $0, delegate: $1)},
		QBECSVSourceStep.className(): {QBECSVStepView(step: $0, delegate: $1)},
		QBEPrestoSourceStep.className(): {QBEPrestoSourceStepView(step: $0, delegate: $1)},
		QBEColumnsStep.className(): {QBEColumnsStepView(step: $0, delegate: $1)},
		QBESortStep.className(): {QBESortStepView(step: $0, delegate: $1)},
		QBEMySQLSourceStep.className(): {QBEMySQLSourceStepView(step: $0, delegate: $1)},
		QBEJoinStep.className(): {QBEJoinStepView(step: $0, delegate: $1)},
		QBEPostgresSourceStep.className(): {QBEPostgresStepView(step: $0, delegate: $1)},
		QBERenameStep.className(): {QBERenameStepView(step: $0, delegate: $1)},
		QBECrawlStep.className(): {QBECrawlStepView(step: $0, delegate: $1)},
		QBERethinkSourceStep.className(): { QBERethinkStepView(step: $0, delegate: $1) }
	]
	
	private let stepIcons = [
		QBETransposeStep.className(): "TransposeIcon",
		QBEPivotStep.className(): "PivotIcon",
		QBERandomStep.className(): "RandomIcon",
		QBEFilterStep.className(): "FilterIcon",
		QBELimitStep.className(): "LimitIcon",
		QBEOffsetStep.className(): "LimitIcon",
		QBECSVSourceStep.className(): "CSVIcon",
		QBESQLiteSourceStep.className(): "SQLIcon",
		QBECalculateStep.className(): "CalculateIcon",
		QBEColumnsStep.className(): "ColumnsIcon",
		QBESortColumnsStep.className(): "ColumnsIcon",
		QBEFlattenStep.className(): "FlattenIcon",
		QBEDistinctStep.className(): "DistinctIcon",
		QBEPrestoSourceStep.className(): "PrestoIcon",
		QBERasterStep.className(): "RasterIcon",
		QBESortStep.className(): "SortIcon",
		QBEMySQLSourceStep.className(): "MySQLIcon",
		QBEPostgresSourceStep.className(): "PostgresIcon",
		QBEJoinStep.className(): "JoinIcon",
		QBECloneStep.className(): "CloneIcon",
		QBEDebugStep.className(): "DebugIcon",
		QBERenameStep.className(): "RenameIcon",
		QBEMergeStep.className(): "MergeIcon",
		QBECrawlStep.className(): "CrawlIcon",
		QBESequencerStep.className(): "SequenceIcon",
		QBEDBFSourceStep.className(): "DBFIcon",
		QBEExportStep.className(): "ExportStepIcon",
		QBERethinkSourceStep.className(): "RethinkDBIcon"
	]
	
	var fileExtensionsForWriting: Set<String> { get {
		var exts = Set<String>()
		for writer in fileWriters {
			exts.unionInPlace(writer.fileTypes)
		}
		return exts
	} }
	
	var fileTypesForReading: [String] { get {
		return [String](fileReaders.keys)
	} }
	
	func stepForReadingFile(atURL: NSURL) -> QBEStep? {
		do {
			let type = try NSWorkspace.sharedWorkspace().typeOfFile(atURL.path!)
			if let creator = fileReaders[type] {
				return creator(url: atURL)
			}

			if let p = atURL.path {
				let ext = NSString(string: p).pathExtension
				if let creator = fileReaders[ext] {
					return creator(url: atURL)
				}
			}
		}
		catch { }
		return nil
	}
	
	func fileWriterForType(type: String) -> QBEFileWriter.Type? {
		for writer in fileWriters {
			if writer.fileTypes.contains(type) {
				return writer
			}
		}
		return nil
	}

	func hasViewForStep(step: QBEStep) -> Bool {
		return stepViews[step.self.className] != nil
	}

	func viewForStep(step: QBEStep, delegate: QBESuggestionsViewDelegate) -> NSViewController? {
		if let creator = stepViews[step.self.className] {
			return creator(step: step, delegate: delegate)
		}
		return nil
	}
	
	func iconForStep(step: QBEStep) -> String? {
		return stepIcons[step.className]
	}
	
	func iconForStepType(type: QBEStep.Type) -> String? {
		return stepIcons[type.className()]
	}
}