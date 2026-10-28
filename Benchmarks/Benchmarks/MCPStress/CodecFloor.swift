/// The floor beneath every case: per call, write the request and read the answer's text, with nothing else. A client cannot do less.
func codecFloor(calls: Int, size: Int) -> Duration {
    let line = Payloads.reply(id: 7, size: size)
    var total = 0
    let elapsed = ContinuousClock()
        .measure {
            for id in 0 ..< calls {
                total &+= Payloads.request(id: id, size: size).count
                total &+= Payloads.text(of: line)?.utf8.count ?? -1
            }
        }
    precondition(total > 0)
    keep(total)
    return elapsed
}
