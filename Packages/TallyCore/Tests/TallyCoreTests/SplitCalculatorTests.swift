import XCTest
@testable import TallyCore

final class SplitCalculatorTests: XCTestCase {
    private let a = uuid(1)
    private let b = uuid(2)
    private let c = uuid(3)
    private let d = uuid(4)

    private func sum(_ shares: [UUID: Decimal]) -> Decimal {
        shares.values.reduce(Decimal(0), +)
    }

    // MARK: equalShares

    func testEqualShares_tenDividedByThree_firstMemberGetsTheExtraCent() {
        let shares = SplitCalculator.equalShares(amount: dec("10.00"), among: [a, b, c])
        XCTAssertEqual(shares[a], dec("3.34"))
        XCTAssertEqual(shares[b], dec("3.33"))
        XCTAssertEqual(shares[c], dec("3.33"))
        XCTAssertEqual(sum(shares), dec("10.00"))
    }

    func testEqualShares_orderDecidesWhoGetsTheRemainder() {
        let shares = SplitCalculator.equalShares(amount: dec("10.00"), among: [c, a, b])
        XCTAssertEqual(shares[c], dec("3.34"))
        XCTAssertEqual(shares[a], dec("3.33"))
        XCTAssertEqual(shares[b], dec("3.33"))
    }

    func testEqualShares_multipleRemainderCents() {
        // 0.05 / 3: each gets 0.01, two leftover cents go to the first two.
        let shares = SplitCalculator.equalShares(amount: dec("0.05"), among: [a, b, c])
        XCTAssertEqual(shares[a], dec("0.02"))
        XCTAssertEqual(shares[b], dec("0.02"))
        XCTAssertEqual(shares[c], dec("0.01"))
        XCTAssertEqual(sum(shares), dec("0.05"))
    }

    func testEqualShares_evenSplit() {
        let shares = SplitCalculator.equalShares(amount: dec("100.00"), among: [a, b, c, d])
        for id in [a, b, c, d] { XCTAssertEqual(shares[id], dec("25.00")) }
    }

    func testEqualShares_singleMemberAndNoMembers() {
        XCTAssertEqual(SplitCalculator.equalShares(amount: dec("42.10"), among: [a]), [a: dec("42.10")])
        XCTAssertTrue(SplitCalculator.equalShares(amount: dec("42.10"), among: []).isEmpty)
    }

    func testEqualShares_zeroDecimalCurrency() {
        let shares = SplitCalculator.equalShares(amount: dec("100"), among: [a, b, c], scale: 0)
        XCTAssertEqual(shares[a], dec("34"))
        XCTAssertEqual(shares[b], dec("33"))
        XCTAssertEqual(shares[c], dec("33"))
        XCTAssertEqual(sum(shares), dec("100"))
    }

    func testEqualShares_alwaysSumExactlyToTheAmount() {
        let amounts = ["0.01", "0.02", "0.99", "7.00", "99.99", "100.00", "1234.56", "100000.01"]
        for amount in amounts {
            for count in 1...9 {
                let ids = (1...count).map { uuid($0) }
                let shares = SplitCalculator.equalShares(amount: dec(amount), among: ids)
                XCTAssertEqual(shares.count, count, "\(amount) / \(count)")
                XCTAssertEqual(sum(shares), dec(amount), "\(amount) / \(count)")
                let values = shares.values
                XCTAssertLessThanOrEqual((values.max() ?? 0) - (values.min() ?? 0), dec("0.01"), "\(amount) / \(count)")
                XCTAssertTrue(values.allSatisfy { $0 >= 0 })
            }
        }
    }

    func testEqualShares_amountWithExtraPrecisionIsRoundedToScale() {
        let amount = dec("10.005")
        let shares = SplitCalculator.equalShares(amount: amount, among: [a, b])
        XCTAssertEqual(sum(shares), amount.rounded(scale: 2))
    }

    // MARK: weightedShares / percentageShares

    func testWeightedShares_sumExactlyAndRemainderGoesToFirstInOrder() {
        let weights = [a: dec("1"), b: dec("2"), c: dec("3")]
        let shares = SplitCalculator.weightedShares(amount: dec("100.00"), weights: weights, order: [a, b, c])
        XCTAssertEqual(shares[a], dec("16.67"))
        XCTAssertEqual(shares[b], dec("33.33"))
        XCTAssertEqual(shares[c], dec("50.00"))
        XCTAssertEqual(sum(shares), dec("100.00"))
    }

    func testWeightedShares_defaultOrderIsDeterministicByUUIDString() {
        let weights = [c: dec("1"), a: dec("1"), b: dec("1")]
        let shares = SplitCalculator.weightedShares(amount: dec("10.00"), weights: weights)
        XCTAssertEqual(shares[a], dec("3.34"), "uuid(1) sorts first")
        XCTAssertEqual(shares[b], dec("3.33"))
        XCTAssertEqual(shares[c], dec("3.33"))
    }

    func testWeightedShares_zeroAndNegativeWeightsAreExcluded() {
        let weights = [a: dec("2"), b: dec("1"), c: 0, d: dec("-3")]
        let shares = SplitCalculator.weightedShares(amount: dec("9.00"), weights: weights, order: [a, b, c, d])
        XCTAssertEqual(shares[a], dec("6.00"))
        XCTAssertEqual(shares[b], dec("3.00"))
        XCTAssertNil(shares[c])
        XCTAssertNil(shares[d])
    }

    func testWeightedShares_noPositiveWeightGivesEmptyResult() {
        XCTAssertTrue(SplitCalculator.weightedShares(amount: dec("10"), weights: [a: 0, b: 0]).isEmpty)
        XCTAssertTrue(SplitCalculator.weightedShares(amount: dec("10"), weights: [:]).isEmpty)
    }

    func testWeightedShares_ordersWithoutWeightsAreSkipped() {
        let shares = SplitCalculator.weightedShares(amount: dec("10.00"), weights: [a: dec("1")], order: [a, b])
        XCTAssertEqual(shares, [a: dec("10.00")])
    }

    func testWeightedShares_alwaysSumExactly() {
        let weightSets: [[Decimal]] = [
            [dec("1"), dec("1"), dec("1")],
            [dec("1"), dec("2"), dec("4"), dec("8")],
            [dec("0.3"), dec("0.7")],
            [dec("7"), dec("11"), dec("13"), dec("17"), dec("19")]
        ]
        for amount in ["0.01", "1.00", "33.33", "100.00", "999.99"] {
            for set in weightSets {
                let ids = (1...set.count).map { uuid($0) }
                var weights: [UUID: Decimal] = [:]
                for (index, id) in ids.enumerated() { weights[id] = set[index] }
                let shares = SplitCalculator.weightedShares(amount: dec(amount), weights: weights, order: ids)
                XCTAssertEqual(sum(shares), dec(amount), "\(amount) with \(set)")
            }
        }
    }

    func testPercentageShares_exactPercentages() {
        let shares = SplitCalculator.percentageShares(
            amount: dec("200.00"),
            percentages: [a: dec("50"), b: dec("30"), c: dec("20")],
            order: [a, b, c]
        )
        XCTAssertEqual(shares[a], dec("100.00"))
        XCTAssertEqual(shares[b], dec("60.00"))
        XCTAssertEqual(shares[c], dec("40.00"))
    }

    func testPercentageShares_thirdsSumToAmount() {
        let shares = SplitCalculator.percentageShares(
            amount: dec("10.00"),
            percentages: [a: dec("33.33"), b: dec("33.33"), c: dec("33.33")],
            order: [a, b, c]
        )
        XCTAssertEqual(shares[a], dec("3.34"))
        XCTAssertEqual(shares[b], dec("3.33"))
        XCTAssertEqual(shares[c], dec("3.33"))
        XCTAssertEqual(sum(shares), dec("10.00"))
    }

    func testPercentageShares_notSummingTo100AreNormalised() {
        let shares = SplitCalculator.percentageShares(
            amount: dec("90.00"),
            percentages: [a: dec("50"), b: dec("25")],
            order: [a, b]
        )
        XCTAssertEqual(shares[a], dec("60.00"))
        XCTAssertEqual(shares[b], dec("30.00"))
    }

    func testPercentageShares_uneven3367() {
        let shares = SplitCalculator.percentageShares(
            amount: dec("100.00"),
            percentages: [a: dec("33.33"), b: dec("33.33"), c: dec("33.34")],
            order: [a, b, c]
        )
        XCTAssertEqual(shares[a], dec("33.33"))
        XCTAssertEqual(shares[b], dec("33.33"))
        XCTAssertEqual(shares[c], dec("33.34"))
        XCTAssertEqual(sum(shares), dec("100.00"))
    }

    func testPercentageShares_withoutOrderStillSumsExactly() {
        let shares = SplitCalculator.percentageShares(
            amount: dec("77.77"),
            percentages: [a: dec("12.5"), b: dec("37.5"), c: dec("50")]
        )
        XCTAssertEqual(sum(shares), dec("77.77"))
        XCTAssertEqual(shares.count, 3)
    }

    // MARK: netBalances

    func testNetBalances_singleExpense() {
        let expense = SharedExpense(
            amount: dec("30"),
            payerID: a,
            owed: [a: dec("10"), b: dec("10"), c: dec("10")]
        )
        let balances = SplitCalculator.netBalances(expenses: [expense])
        XCTAssertEqual(balances[a], dec("20"))
        XCTAssertEqual(balances[b], dec("-10"))
        XCTAssertEqual(balances[c], dec("-10"))
    }

    func testNetBalances_multipleExpensesNetOut() {
        let e1 = SharedExpense(amount: dec("60"), payerID: a, owed: [a: dec("30"), b: dec("30")])
        let e2 = SharedExpense(amount: dec("40"), payerID: b, owed: [a: dec("20"), b: dec("20")])
        let balances = SplitCalculator.netBalances(expenses: [e1, e2])
        XCTAssertEqual(balances[a], dec("10"))
        XCTAssertEqual(balances[b], dec("-10"))
    }

    func testNetBalances_withSettlements() {
        let expense = SharedExpense(amount: dec("30"), payerID: a, owed: [a: dec("10"), b: dec("10"), c: dec("10")])
        let settlement = SettlementRecord(fromID: b, toID: a, amount: dec("10"))
        let balances = SplitCalculator.netBalances(expenses: [expense], settlements: [settlement])
        XCTAssertEqual(balances[a], dec("10"))
        XCTAssertEqual(balances[b], 0)
        XCTAssertEqual(balances[c], dec("-10"))
    }

    func testNetBalances_fullSettlementZeroesEveryone() {
        let expense = SharedExpense(amount: dec("50"), payerID: a, owed: [a: dec("25"), b: dec("25")])
        let settlement = SettlementRecord(fromID: b, toID: a, amount: dec("25"))
        let balances = SplitCalculator.netBalances(expenses: [expense], settlements: [settlement])
        XCTAssertEqual(balances[a], 0)
        XCTAssertEqual(balances[b], 0)
    }

    func testNetBalances_noInput() {
        XCTAssertTrue(SplitCalculator.netBalances(expenses: []).isEmpty)
    }

    func testNetBalances_alwaysSumToZeroWhenOwedMatchesAmount() {
        let e1 = SharedExpense(amount: dec("100.00"), payerID: a, owed: SplitCalculator.equalShares(amount: dec("100.00"), among: [a, b, c]))
        let e2 = SharedExpense(amount: dec("61.01"), payerID: c, owed: SplitCalculator.equalShares(amount: dec("61.01"), among: [a, c, d]))
        let balances = SplitCalculator.netBalances(expenses: [e1, e2])
        XCTAssertEqual(sum(balances), 0)
    }

    // MARK: settleUp

    private func apply(_ transfers: [SettleUpTransfer], to balances: [UUID: Decimal]) -> [UUID: Decimal] {
        var result = balances
        for transfer in transfers {
            result[transfer.fromID, default: 0] += transfer.amount
            result[transfer.toID, default: 0] -= transfer.amount
        }
        return result
    }

    func testSettleUp_simpleTwoPersonCase() {
        let expense = SharedExpense(amount: dec("50.00"), payerID: a, owed: [a: dec("25.00"), b: dec("25.00")])
        let balances = SplitCalculator.netBalances(expenses: [expense])
        let transfers = SplitCalculator.settleUp(balances: balances)
        XCTAssertEqual(transfers.count, 1)
        XCTAssertEqual(transfers[0].fromID, b)
        XCTAssertEqual(transfers[0].toID, a)
        XCTAssertEqual(transfers[0].amount, dec("25.00"))
        XCTAssertEqual(transfers[0].id, "\(b)-\(a)")
    }

    func testSettleUp_nothingToDoWhenSettled() {
        XCTAssertTrue(SplitCalculator.settleUp(balances: [:]).isEmpty)
        XCTAssertTrue(SplitCalculator.settleUp(balances: [a: 0, b: 0]).isEmpty)
        let expense = SharedExpense(amount: dec("50"), payerID: a, owed: [a: dec("25"), b: dec("25")])
        let settled = SplitCalculator.netBalances(
            expenses: [expense],
            settlements: [SettlementRecord(fromID: b, toID: a, amount: dec("25"))]
        )
        XCTAssertTrue(SplitCalculator.settleUp(balances: settled).isEmpty)
    }

    func testSettleUp_ignoresBalancesSmallerThanOneUnit() {
        XCTAssertTrue(SplitCalculator.settleUp(balances: [a: dec("0.004"), b: dec("-0.004")]).isEmpty)
    }

    func testSettleUp_matchesLargestDebtorWithLargestCreditorFirst() {
        let balances = [a: dec("50"), b: dec("30"), c: dec("-20"), d: dec("-60")]
        let transfers = SplitCalculator.settleUp(balances: balances)
        XCTAssertEqual(transfers.count, 3)
        XCTAssertEqual(transfers[0].fromID, d)
        XCTAssertEqual(transfers[0].toID, a)
        XCTAssertEqual(transfers[0].amount, dec("50"))
        XCTAssertEqual(transfers[1].fromID, c)
        XCTAssertEqual(transfers[1].toID, b)
        XCTAssertEqual(transfers[1].amount, dec("20"))
        XCTAssertEqual(transfers[2].fromID, d)
        XCTAssertEqual(transfers[2].toID, b)
        XCTAssertEqual(transfers[2].amount, dec("10"))
        for balance in apply(transfers, to: balances).values { XCTAssertEqual(balance, 0) }
    }

    func testSettleUp_transfersZeroEveryBalance_afterApplying() {
        let balances = [a: dec("66.66"), b: dec("-33.33"), c: dec("-33.33")]
        let transfers = SplitCalculator.settleUp(balances: balances)
        XCTAssertEqual(transfers.count, 2)
        let after = apply(transfers, to: balances)
        for id in [a, b, c] { XCTAssertEqual(after[id], 0, "\(id)") }
        XCTAssertTrue(transfers.allSatisfy { $0.amount > 0 })
    }

    func testSettleUp_endToEndScenario() {
        let members = [a, b, c, d]
        let expenses = [
            SharedExpense(amount: dec("100.00"), payerID: a, owed: SplitCalculator.equalShares(amount: dec("100.00"), among: members)),
            SharedExpense(amount: dec("61.00"), payerID: b, owed: SplitCalculator.equalShares(amount: dec("61.00"), among: [a, b, c])),
            SharedExpense(amount: dec("45.50"), payerID: c, owed: SplitCalculator.equalShares(amount: dec("45.50"), among: [b, c, d])),
            SharedExpense(
                amount: dec("80.00"),
                payerID: d,
                owed: SplitCalculator.percentageShares(
                    amount: dec("80.00"),
                    percentages: [a: dec("10"), b: dec("20"), c: dec("30"), d: dec("40")],
                    order: members
                )
            )
        ]
        let settlements = [SettlementRecord(fromID: c, toID: a, amount: dec("5.00"))]
        let balances = SplitCalculator.netBalances(expenses: expenses, settlements: settlements)
        XCTAssertEqual(sum(balances), 0)

        let transfers = SplitCalculator.settleUp(balances: balances)
        XCTAssertLessThanOrEqual(transfers.count, members.count - 1)
        let after = apply(transfers, to: balances)
        for id in members {
            XCTAssertEqual(after[id] ?? 0, 0, "balance of \(id) after settling")
        }
        for transfer in transfers {
            XCTAssertNotEqual(transfer.fromID, transfer.toID)
            XCTAssertGreaterThan(transfer.amount, 0)
        }
    }

    func testSettleUp_zeroDecimalScale() {
        let transfers = SplitCalculator.settleUp(balances: [a: dec("10"), b: dec("-10")], scale: 0)
        XCTAssertEqual(transfers.count, 1)
        XCTAssertEqual(transfers[0].amount, dec("10"))
    }

    func testSplitMethodMetadata() {
        XCTAssertEqual(SplitMethod.allCases.count, 4)
        for method in SplitMethod.allCases {
            XCTAssertFalse(method.displayName.isEmpty)
            XCTAssertEqual(method.id, method.rawValue)
        }
    }
}
