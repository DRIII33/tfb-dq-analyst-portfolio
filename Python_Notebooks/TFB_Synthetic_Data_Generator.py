#INSTALL PACKAGES
!pip install pandas numpy
---

import pandas as pd
import numpy as np
import random
from datetime import datetime, timedelta

def generate_tfb_data(records=5000):
    """
    Generates synthetic underwriting data aligned with 2026 TDI Section E.
    Includes intentional anomalies for DQ profiling.
    """
    np.random.seed(42)

    # [8, 14]: Defining the valid codes and parameters
    action_types = ['C', 'NR', 'D'] # From TDI Section E, ACTION_TYPE
    policy_types = ['H', 'D', 'T', 'C'] # From TDI Section E, POLICY_TYPE
    reason_codes_pool = list("ABCDEFGHIJKL")
    texas_zips = ['76701', '76710', '76712', '75201', '77002', '78701', '79901', '78205']

    data = [] # Initialize data as an empty list

    # : Reporting for periods beginning April 1, 2026
    start_date = datetime(2026, 1, 1)
    end_date = datetime(2026, 4, 30)

    for i in range(records):
        # Timestamps
        notification_date = start_date + timedelta(days=random.randint(0, 110))
        effective_date = notification_date + timedelta(days=random.randint(15, 90))

        # : Logic for 60-day indicator
        indicator_60d = 1 if (effective_date - notification_date).days >= 60 else 0

        # : Reason code concatenation (Must be alphabetical)
        num_reasons = random.randint(1, 3)
        selected_codes = sorted(random.sample(reason_codes_pool, num_reasons))
        reason_string = "".join(selected_codes)

        # [16]: Third-party data logic
        third_party = 'Y' if random.random() > 0.4 else 'N'
        aerial = 0
        if 'K' in reason_string and third_party == 'Y':
            # : TFB uses satellite imagery for roof assessments
            aerial = 1 if random.random() > 0.2 else 0

        # Injecting Data Quality Issues for Profiling
        dq_noise = random.random()
        zip_val = random.choice(texas_zips)

        if dq_noise < 0.02: # 2% Missing ZIPs
            zip_val = None
        elif dq_noise < 0.04: # 2% Invalid Reason Codes (non-alphabetical)
            reason_string = "".join(reversed(selected_codes))
        elif dq_noise < 0.06: # 2% Date mismatches
            effective_date = notification_date - timedelta(days=5)

        data.append({
            'RECORD_ID': f'TFB-{100000 + i}',
            'POLICY_NUMBER': f'POL-{random.randint(500000, 999999)}',
            'NOTIFICATION_DATE': notification_date.strftime('%Y-%m-%d'),
            'ACTION_TYPE': random.choice(action_types),
            'POLICY_TYPE': random.choice(policy_types),
            'REASON_SOURCE': random.choice(['C', 'A', 'B']), # From TDI Section E, REASON_SOURCE
            'INDICATOR_60D': indicator_60d,
            'ZIP_CODE': zip_val,
            'EFFECTIVE_DATE': effective_date.strftime('%Y-%m-%d'),
            'REASON_CODES': reason_string,
            'THIRD_PARTY_IND': third_party,
            'AERIAL_IMAGERY': aerial
        })

    df = pd.DataFrame(data)
    df.to_csv('tfb_adverse_actions_raw.csv', index=False)
    print(f"Generated {records} records. Saved to tfb_adverse_actions_raw.csv")
    return df

# Run the generator
tfb_df = generate_tfb_data()
print(tfb_df.head(10))
