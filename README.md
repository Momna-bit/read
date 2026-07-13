Subject: Call Volume Forecasting - Summary & How It Works

Hi Jonathan,

Here is the full write-up of the call forecasting work, including a plain-English explanation of how the prediction works so it's easy to share with stakeholders.

WHAT WAS BUILT

A model that predicts how many Care calls we'll get on any given day, so staffing can be planned ahead of time instead of reacting after the fact.

Data source: this is based entirely on dbo.IVR (the raw call log) - every agent-handled Inbound/Transfer call in Care (AgentTalkTime > 0). It is not limited to calls reviewed by the AI classification pipeline (Care_CallAI); that table is used for a separate analysis (the Spanish-language bill-explanation work), where we needed to know why a customer called. For forecasting, we only needed to know how many calls happened, so the raw IVR log was the right and complete source.

HOW THE PREDICTION WORKS (PLAIN ENGLISH)

Think of it in two steps:

1. How many customers could call us today? We count active Texas residential customers each day (roughly 640,000, fairly stable).

2. What's a typical day like this? We looked at history and found a clear weekly rhythm - Monday is consistently the busiest day, and call volume steadily tapers off through the week, dropping sharply on weekends (Sunday is essentially zero).

The prediction simply combines these two: expected customers x that day's typical calling rate = predicted calls. It's the same logic as predicting foot traffic at a store - busier on some days of the week than others, and that pattern repeats.

ACCURACY

We tested the model against real, already-known history to see how close its predictions would have been. On normal days, it's accurate to within about 7.7% - solid enough to use for staffing decisions.

The two days it misses both make sense: it over-predicts on the holiday itself (July 4th - expected a normal Saturday, got a quieter one), and under-predicts the day after (the post-holiday Monday surge). Both of these match the abandonment-rate spike found earlier this week, which is a good sign the model is picking up something real rather than noise.

14-DAY FORECAST

Date | Day | Predicted Calls
Jul 11 | Sat | 1,146
Jul 12 | Sun | 0
Jul 13 | Mon | 4,447
Jul 14 | Tue | 3,513
Jul 15 | Wed | 3,312
Jul 16 | Thu | 2,816
Jul 17 | Fri | 2,698
Jul 18 | Sat | 1,146
Jul 19 | Sun | 0
Jul 20 | Mon | 4,447
Jul 21 | Tue | 3,513
Jul 22 | Wed | 3,312
Jul 23 | Thu | 2,816
Jul 24 | Fri | 2,698

Note: Jul 21-24 repeat the same values as the prior week, since this first version assumes a flat customer count and doesn't yet vary week to week. A natural next refinement is updating that with a live customer count and explicit holiday flags to fix the two known gaps above.

NEXT STEPS

1. Add holiday / day-after-holiday flags to tighten accuracy on those two known gaps
2. Layer in customer-level attributes (product, channel, tenure, split-bill status) to move toward understanding which customers are likely to call - already underway
3. Track predicted-vs-actual on an ongoing basis, especially once the payment-arrangement terms change and the multilingual portal ship, both of which are expected to reduce call volume

Happy to walk through any of this in more detail or answer questions.

Thanks,
Momna
