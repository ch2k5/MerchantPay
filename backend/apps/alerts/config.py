"""
Configurable thresholds and parameters for the Merchant Alert Rule Engine.
"""

# 1. REVENUE_DROP
REVENUE_DROP_WARNING_THRESHOLD_PCT = 10.0  # >= 10% drop triggers WARNING
REVENUE_DROP_CRITICAL_THRESHOLD_PCT = 25.0  # >= 25% drop triggers CRITICAL

# 2. NO_ACTIVITY
NO_ACTIVITY_DAYS_THRESHOLD = 5  # >= 5 days without any transaction triggers CRITICAL

# 3. REJECTION_SPIKE
REJECTION_SPIKE_DIFF_POINTS = 5.0  # >= previous rate + 5 percentage points
REJECTION_SPIKE_RATIO_MULTIPLIER = 1.5  # >= 1.5x previous rejection rate
REJECTION_SPIKE_MIN_TRANSACTIONS = 10  # minimum current transactions to evaluate

# 4. GOAL_PROGRESS
GOAL_PROGRESS_INFO_PCT = 85.0  # >= 85% goal progress -> INFO
GOAL_PROGRESS_SUCCESS_PCT = 100.0  # >= 100% goal progress -> SUCCESS
GOAL_PROGRESS_LATE_MONTH_DAY = 20  # day of month threshold
GOAL_PROGRESS_LATE_MONTH_MIN_PCT = 60.0  # if past day 20 and progress < 60% -> WARNING

# 5. CHANNEL_SHIFT
CHANNEL_SHIFT_THRESHOLD_POINTS = 15.0  # change in channel share >= 15 points
