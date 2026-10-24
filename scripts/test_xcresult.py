import unittest
from check_xcresult import validate


class XCTestResultTests(unittest.TestCase):
    def test_modern_result(self):
        self.assertIn("20 passed", validate({"totalTestCount": 20, "passedTests": 20, "failedTests": 0}))

    def test_legacy_result(self):
        self.assertIn("20 passed", validate({"metrics": {"testsCount": {"_value": "20"}}}))

    def test_zero_or_all_skipped_is_not_success(self):
        for total, skipped in [(0, 0), (9, 9)]:
            with self.assertRaises(ValueError):
                validate({"totalTestCount": total, "passedTests": 0, "failedTests": 0, "skippedTests": skipped})

    def test_nonzero_failure_is_rejected(self):
        with self.assertRaises(ValueError):
            validate({"totalTestCount": 21, "passedTests": 20, "failedTests": 1})


if __name__ == "__main__":
    unittest.main()
