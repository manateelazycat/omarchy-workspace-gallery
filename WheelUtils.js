function getSteps(delta, accumulator) {
    var total = Number(accumulator || 0) + Number(delta || 0)
    var steps = total > 0 ? Math.floor(total / 120) : Math.ceil(total / 120)
    return { steps: steps, accumulator: total - steps * 120 }
}
