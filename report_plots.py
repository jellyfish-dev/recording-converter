import csv
import matplotlib.pyplot as plt

# Mbps
LOW = 0.15
MID = 0.5
HIGH = 1.5


report = []
with open("../report.csv", mode="r") as file:
    csvFile = csv.DictReader(file)
    for line in csvFile:
        report.append(line)

timestamps = list(map(lambda a: int(a["timestamp"]), report))
min_curve = list(map(lambda a: float(a["min"]), report))
max_curve = list(map(lambda a: float(a["max"]), report))
q1_curve = list(map(lambda a: float(a["q1"]), report))
q2_curve = list(map(lambda a: float(a["q2"]), report))
q3_curve = list(map(lambda a: float(a["q3"]), report))

encoding_low = list(map(lambda a: int(a["low"]), report))
encoding_medium = list(map(lambda a: int(a["mid"]), report))
encoding_high = list(map(lambda a: int(a["high"]), report))

bandwidth = list(map(lambda a: int(a["low"]) * LOW + int(a["mid"]) * MID + int(a["high"]) * HIGH, report))

# Plotting the arrays
plt.plot(timestamps, min_curve, label="minimum")
plt.plot(timestamps, max_curve, label="maximum")
plt.plot(timestamps, q1_curve, label="Q1")
plt.plot(timestamps, q2_curve, label="median")
plt.plot(timestamps, q3_curve, label="Q3")

plt.xlabel("Timestamp")
plt.ylabel("RTC Score")
plt.legend()

plt.show()

plt.figure()
plt.plot(timestamps, encoding_low, label="low")
plt.plot(timestamps, encoding_medium, label="medium")
plt.plot(timestamps, encoding_high, label="high")

plt.xlabel("Timestamp")
plt.ylabel("Encodings")
plt.legend()

plt.show()


plt.figure()
plt.plot(timestamps, bandwidth, label="low")

plt.xlabel("Timestamp")
plt.ylabel("Bandwidth")
plt.legend()

plt.show()