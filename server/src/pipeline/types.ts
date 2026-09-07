export interface PrintedRange {
  low: number | null;
  high: number | null;
  text?: string; // raw text when the printed range isn't a clean [low, high], e.g. "*Refer Note below"
}

export interface ExtractedTuple {
  label_as_printed: string;
  value: string; // kept as string — could be numeric or qualitative ("Nil", "Reactive")
  unit: string | null;
  printed_reference_range: PrintedRange | null;
  extraction_confidence: number; // 0-1, how confident the extractor is in this specific reading
}

export interface LabExtractionResult {
  presentation_style: 'tabular' | 'chart_infographic' | 'narrative_handwritten';
  lab_visit_id: string | null;
  test_date: string | null; // ISO date the sample was collected/reported
  ordering_lab_name: string | null;
  tuples: ExtractedTuple[];
}

export interface PrescriptionLineItemExtracted {
  medicine_name: string;
  dosage: string | null;
  frequency: string | null;
  duration: string | null;
}

export interface PrescriptionExtractionResult {
  diagnosis_text: string | null;
  prescribed_date: string | null;
  line_items: PrescriptionLineItemExtracted[];
}

export interface ExtractOptions {
  /** Dev/demo hook only: forces the mock adapter to replay a specific golden fixture
   * instead of synthesizing random data. Ignored by the real Claude adapter. */
  mockFixture?: 'golden_report_a' | 'golden_report_b';
}

export interface ExtractAdapter {
  extractLabReport(pages: PageInput[], opts?: ExtractOptions): Promise<LabExtractionResult>;
  extractPrescription(pages: PageInput[], opts?: ExtractOptions): Promise<PrescriptionExtractionResult>;
}

export interface PageInput {
  buffer: Buffer;
  mimeType: string;
}

export interface MatchResult {
  canonical_parameter_id: string | null;
  match_tier: 1 | 2 | 3 | null;
  match_confidence: number; // 0 when no match
}
