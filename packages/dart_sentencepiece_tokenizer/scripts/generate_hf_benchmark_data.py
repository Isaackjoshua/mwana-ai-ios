#!/usr/bin/env python3
"""
Generate HuggingFace SentencePiece tokenizer benchmark data.

This script generates the expected tokenization results from HuggingFace's
SentencePiece tokenizer for use in compatibility benchmarks.

Requirements:
    pip install sentencepiece transformers

Usage:
    python scripts/generate_hf_benchmark_data.py --model <model_path>

Output:
    hf_sp_benchmark_data.json - JSON file with expected tokenization results
"""

import argparse
import json
import sys
from pathlib import Path

try:
    import sentencepiece as spm
except ImportError:
    print("ERROR: sentencepiece package not installed.")
    print("Run: pip install sentencepiece")
    sys.exit(1)


# =============================================================================
# TEST CASES
# =============================================================================

SINGLE_ENCODING_TESTS = [
    # Basic text
    ("Simple greeting", "Hello, world!"),
    ("Classic pangram", "The quick brown fox jumps over the lazy dog."),
    ("Simple sentence", "This is a test."),

    # Subword tokenization
    ("Subword tokenization", "tokenization"),
    ("Complex subword", "unbelievable"),
    ("Long subword", "internationalization"),
    ("Technical term", "preprocessing"),

    # Numbers
    ("Single digit", "5"),
    ("Multiple digits", "12345"),
    ("Year", "2024"),
    ("Decimal number", "3.14159"),

    # Punctuation
    ("Multiple punctuation", "!!??"),
    ("Ellipsis", "..."),
    ("Mixed punctuation", "Hello... World!"),
    ("Punctuation only", ".,!?;:"),

    # LLM related text
    ("LLM prompt", "What is machine learning?"),
    ("AI sentence", "Artificial intelligence is transforming the world."),
    ("NLP text", "Natural language processing enables computers to understand."),
    ("Model name", "GPT and BERT are transformer models."),

    # Code-like text
    ("Code snippet", "def hello(): print('world')"),
    ("Variable name", "my_variable_name"),
    ("CamelCase", "camelCaseVariable"),
    ("Function call", "calculate_sum(a, b)"),

    # Special characters
    ("At symbol", "user@example.com"),
    ("Hashtag", "#trending"),
    ("Currency", "$100.50"),
    ("Percentage", "50%"),
    ("Ampersand", "A & B"),

    # Unicode and accents
    ("Accented cafe", "café"),
    ("Accented naive", "naïve"),
    ("Accented resume", "résumé"),
    ("German umlaut", "München"),
    ("Spanish tilde", "piñata"),
    ("French accent", "fiancée"),

    # Multi-language
    ("Chinese characters", "你好世界"),
    ("Japanese hiragana", "こんにちは"),
    ("Korean", "안녕하세요"),
    ("Mixed language", "Hello 世界 Bonjour"),
    ("Russian", "Привет мир"),

    # Emoji
    ("Simple emoji", "Hello 😊"),
    ("Multiple emoji", "🎉🎊🎈"),
    ("Emoji in text", "I love ❤️ coding"),

    # Contractions
    ("Contraction I'm", "I'm happy"),
    ("Contraction don't", "don't worry"),
    ("Contraction won't", "won't happen"),
    ("Contraction it's", "it's great"),
    ("Contraction they're", "they're coming"),

    # Hyphenated words
    ("Hyphenated state", "state-of-the-art"),
    ("Hyphenated well", "well-known"),
    ("Hyphenated self", "self-driving"),

    # Quotes
    ("Double quoted", '"Hello"'),
    ("Single quoted", "'Hello'"),
    ("Quote in sentence", "He said 'hello'"),

    # URLs and emails
    ("Simple URL", "https://example.com"),
    ("Complex URL", "https://www.example.com/path?query=value"),
    ("Email address", "test@example.com"),

    # Long text
    ("Long sentence", "Machine learning is a subset of artificial intelligence that enables systems to learn and improve from experience without being explicitly programmed."),
    ("Paragraph", "The quick brown fox jumps over the lazy dog. This sentence contains every letter of the English alphabet."),

    # Case variations
    ("All caps", "HELLO WORLD"),
    ("Mixed case", "HeLLo WoRLd"),
    ("Title case", "Hello World"),

    # Repeated patterns
    ("Repeated char", "aaaaaaaaaa"),
    ("Repeated word", "test test test"),

    # Technical terms
    ("Scientific", "deoxyribonucleic acid"),
    ("Medical", "pneumonoultramicroscopicsilicovolcanoconiosis"),

    # Math expressions
    ("Math simple", "1 + 2 = 3"),
    ("Math complex", "x^2 + y^2 = z^2"),

    # Programming keywords
    ("Python keywords", "if else for while def class"),
    ("JavaScript keywords", "const let var function async await"),
]

EDGE_CASE_TESTS = [
    ("Empty string", ""),
    ("Single space", " "),
    ("Multiple spaces", "   "),
    ("Tab character", "\t"),
    ("Newline", "\n"),
    ("Tab and newline", "\t\n"),
    ("Single character a", "a"),
    ("Single character z", "z"),
    ("Single punctuation period", "."),
    ("Single punctuation exclaim", "!"),
    ("Multiple spaces between", "hello    world"),
    ("Leading spaces", "   hello"),
    ("Trailing spaces", "hello   "),
    ("Only newlines", "\n\n\n"),
    ("Mixed whitespace", " \t \n "),
    ("Very long word", "a" * 50),
    ("Repeated word long", "test " * 20),
    ("Single number", "0"),
    ("Negative number", "-123"),
    ("Scientific notation", "1.23e-4"),
]

NORMALIZATION_TESTS = [
    ("Leading space", " hello"),
    ("Trailing space", "hello "),
    ("Multiple internal spaces", "hello   world"),
    ("Tabs to spaces", "hello\tworld"),
    ("Newline handling", "hello\nworld"),
    ("Unicode space", "hello\u00A0world"),  # Non-breaking space
    ("Zero-width space", "hello\u200Bworld"),
    ("Em dash", "hello—world"),
    ("En dash", "hello–world"),
]

OFFSET_TESTS = [
    ("Single word", "hello"),
    ("Two words", "hello world"),
    ("Three words", "hello world test"),
    ("With punctuation", "hello, world!"),
    ("Subword split", "tokenization"),
]


def load_sentencepiece_model(model_path: str) -> spm.SentencePieceProcessor:
    """Load a SentencePiece model from file."""
    sp = spm.SentencePieceProcessor()
    sp.Load(model_path)
    return sp


def encode_text(sp: spm.SentencePieceProcessor, text: str) -> dict:
    """Encode text and return detailed results."""
    pieces = sp.EncodeAsPieces(text)
    ids = sp.EncodeAsIds(text)

    return {
        "tokens": pieces,
        "ids": ids,
        "num_tokens": len(pieces),
    }


def run_single_encoding_tests(
    sp: spm.SentencePieceProcessor,
) -> list[dict]:
    """Run single encoding tests."""
    results = []

    for name, text in SINGLE_ENCODING_TESTS:
        try:
            encoding = encode_text(sp, text)
            result = {
                "name": name,
                "input": text,
                "tokens": encoding["tokens"],
                "ids": encoding["ids"],
                "success": True,
            }
        except Exception as e:
            result = {
                "name": name,
                "input": text,
                "error": str(e),
                "success": False,
            }
        results.append(result)

    return results


def run_edge_case_tests(
    sp: spm.SentencePieceProcessor,
) -> list[dict]:
    """Run edge case tests."""
    results = []

    for name, text in EDGE_CASE_TESTS:
        try:
            encoding = encode_text(sp, text)
            result = {
                "name": name,
                "input": text,
                "input_repr": repr(text),
                "tokens": encoding["tokens"],
                "ids": encoding["ids"],
                "success": True,
            }
        except Exception as e:
            result = {
                "name": name,
                "input": text,
                "input_repr": repr(text),
                "error": str(e),
                "success": False,
            }
        results.append(result)

    return results


def run_normalization_tests(
    sp: spm.SentencePieceProcessor,
) -> list[dict]:
    """Run normalization tests."""
    results = []

    for name, text in NORMALIZATION_TESTS:
        try:
            encoding = encode_text(sp, text)
            result = {
                "name": name,
                "input": text,
                "input_repr": repr(text),
                "tokens": encoding["tokens"],
                "ids": encoding["ids"],
                "success": True,
            }
        except Exception as e:
            result = {
                "name": name,
                "input": text,
                "input_repr": repr(text),
                "error": str(e),
                "success": False,
            }
        results.append(result)

    return results


def run_offset_tests(
    sp: spm.SentencePieceProcessor,
) -> list[dict]:
    """Run offset mapping tests."""
    results = []

    for name, text in OFFSET_TESTS:
        try:
            pieces = sp.EncodeAsPieces(text)
            ids = sp.EncodeAsIds(text)

            result = {
                "name": name,
                "input": text,
                "tokens": pieces,
                "ids": ids,
                "success": True,
            }
        except Exception as e:
            result = {
                "name": name,
                "input": text,
                "error": str(e),
                "success": False,
            }
        results.append(result)

    return results


def get_model_info(sp: spm.SentencePieceProcessor) -> dict:
    """Get model information."""
    return {
        "vocab_size": sp.GetPieceSize(),
        "bos_id": sp.bos_id(),
        "eos_id": sp.eos_id(),
        "pad_id": sp.pad_id(),
        "unk_id": sp.unk_id(),
        "bos_piece": sp.IdToPiece(sp.bos_id()) if sp.bos_id() >= 0 else None,
        "eos_piece": sp.IdToPiece(sp.eos_id()) if sp.eos_id() >= 0 else None,
        "unk_piece": sp.IdToPiece(sp.unk_id()) if sp.unk_id() >= 0 else None,
    }


def generate_dart_test_code(results: dict) -> str:
    """Generate Dart test code from results."""
    lines = [
        "// Auto-generated SentencePiece compatibility test cases",
        "// Generated from HuggingFace SentencePiece tokenizer",
        "",
        "const singleEncodingTestCases = [",
    ]

    for r in results.get("single_encoding", []):
        if not r.get("success"):
            continue
        name = r["name"].replace("'", "\\'")
        input_text = r["input"].replace("'", "\\'").replace("\n", "\\n")
        tokens = json.dumps(r["tokens"])
        ids = r["ids"]

        lines.append(f"  SingleEncodingTestCase(")
        lines.append(f"    name: '{name}',")
        lines.append(f"    input: '{input_text}',")
        lines.append(f"    expectedTokens: {tokens},")
        lines.append(f"    expectedIds: {ids},")
        lines.append(f"  ),")

    lines.append("];")
    lines.append("")

    lines.append("const edgeCaseTestCases = [")
    for r in results.get("edge_cases", []):
        if not r.get("success"):
            continue
        name = r["name"].replace("'", "\\'")
        input_repr = r.get("input_repr", repr(r["input"]))
        tokens = json.dumps(r["tokens"])
        ids = r["ids"]

        lines.append(f"  EdgeCaseTestCase(")
        lines.append(f"    name: '{name}',")
        lines.append(f"    input: {input_repr},")
        lines.append(f"    expectedTokens: {tokens},")
        lines.append(f"    expectedIds: {ids},")
        lines.append(f"  ),")

    lines.append("];")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Generate HuggingFace SentencePiece benchmark data"
    )
    parser.add_argument(
        "--model",
        required=True,
        help="Path to SentencePiece .model file",
    )
    parser.add_argument(
        "--output",
        default="hf_sp_benchmark_data.json",
        help="Output JSON file path",
    )
    parser.add_argument(
        "--dart-output",
        help="Optional: Generate Dart test code file",
    )
    args = parser.parse_args()

    model_path = Path(args.model)
    if not model_path.exists():
        print(f"ERROR: Model file not found: {model_path}")
        sys.exit(1)

    print("=" * 70)
    print("HuggingFace SentencePiece Benchmark Data Generator")
    print("=" * 70)
    print(f"Model: {model_path}")
    print()

    print("Loading SentencePiece model...")
    sp = load_sentencepiece_model(str(model_path))

    model_info = get_model_info(sp)
    print(f"Vocabulary size: {model_info['vocab_size']}")
    print(f"BOS ID: {model_info['bos_id']} ({model_info['bos_piece']})")
    print(f"EOS ID: {model_info['eos_id']} ({model_info['eos_piece']})")
    print(f"UNK ID: {model_info['unk_id']} ({model_info['unk_piece']})")
    print()

    results = {
        "model_info": model_info,
        "single_encoding": [],
        "edge_cases": [],
        "normalization": [],
        "offset_tests": [],
    }

    print("-" * 70)
    print("1. SINGLE ENCODING TESTS")
    print("-" * 70)
    results["single_encoding"] = run_single_encoding_tests(sp)
    success = sum(1 for r in results["single_encoding"] if r.get("success"))
    print(f"  Completed: {success}/{len(SINGLE_ENCODING_TESTS)}")

    for r in results["single_encoding"][:5]:
        if r.get("success"):
            print(f"    {r['name']}: {r['tokens'][:5]}...")

    print()

    print("-" * 70)
    print("2. EDGE CASE TESTS")
    print("-" * 70)
    results["edge_cases"] = run_edge_case_tests(sp)
    success = sum(1 for r in results["edge_cases"] if r.get("success"))
    print(f"  Completed: {success}/{len(EDGE_CASE_TESTS)}")
    print()

    print("-" * 70)
    print("3. NORMALIZATION TESTS")
    print("-" * 70)
    results["normalization"] = run_normalization_tests(sp)
    success = sum(1 for r in results["normalization"] if r.get("success"))
    print(f"  Completed: {success}/{len(NORMALIZATION_TESTS)}")
    print()

    print("-" * 70)
    print("4. OFFSET TESTS")
    print("-" * 70)
    results["offset_tests"] = run_offset_tests(sp)
    success = sum(1 for r in results["offset_tests"] if r.get("success"))
    print(f"  Completed: {success}/{len(OFFSET_TESTS)}")
    print()

    output_path = Path(args.output)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print(f"Results saved to: {output_path}")

    if args.dart_output:
        dart_code = generate_dart_test_code(results)
        dart_path = Path(args.dart_output)
        with open(dart_path, "w", encoding="utf-8") as f:
            f.write(dart_code)
        print(f"Dart test code saved to: {dart_path}")

    print()
    print("=" * 70)
    print("SUMMARY")
    print("=" * 70)
    total = (
        len(results["single_encoding"])
        + len(results["edge_cases"])
        + len(results["normalization"])
        + len(results["offset_tests"])
    )
    success_total = (
        sum(1 for r in results["single_encoding"] if r.get("success"))
        + sum(1 for r in results["edge_cases"] if r.get("success"))
        + sum(1 for r in results["normalization"] if r.get("success"))
        + sum(1 for r in results["offset_tests"] if r.get("success"))
    )
    print(f"Total test cases: {total}")
    print(f"Successful: {success_total}")
    print(f"Failed: {total - success_total}")


if __name__ == "__main__":
    main()
