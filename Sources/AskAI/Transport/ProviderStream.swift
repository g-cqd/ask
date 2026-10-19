/// A provider's response, streamed over HTTP as server-sent events and decoded into neutral ``ModelEvent``s.
///
/// Everything here is the same for every provider; what differs is the decoder, which knows the protocol, and the
/// statuses the provider calls success.
enum ProviderStream {
    /// Sends `http` and streams the decoded events. The stream throws a ``ProviderStreamError``.
    static func events<Decoder: ModelEventDecoding>(
        _ http: HTTPRequest, over transport: any HTTPTransport, decoder: Decoder.Type,
        succeeds: @escaping @Sendable (Int) -> Bool
    ) -> AsyncThrowingStream<ModelEvent, any Error> {
        .producing { yield in
            let response: HTTPStreamingResponse
            do {
                response = try await transport.send(http)
            } catch let error as CancellationError {
                throw error
            } catch {
                throw ProviderStreamError<Decoder.Failure>.transport(String(describing: error))
            }
            guard succeeds(response.status) else {
                let (body, retryAfter) = await response.rejection()
                throw ProviderStreamError<Decoder.Failure>
                    .status(
                        response.status, Decoder.failure(inErrorBody: body), retryAfter: retryAfter)
            }
            try await pump(response.body, into: Decoder(), yield: yield)
        }
    }

    /// Frames `body`, decodes each event, and yields the events as soon as each chunk is decoded.
    private static func pump<Decoder: ModelEventDecoding>(
        _ body: AsyncThrowingStream<[UInt8], any Error>, into decoder: Decoder, yield: (ModelEvent) -> Void
    ) async throws {
        var decoder = decoder
        var framer = SSEDecoder()
        var frames: [SSEEvent] = []
        var events: [ModelEvent] = []
        for try await chunk in body {
            do {
                try framer.feed(chunk.span, into: &frames)
            } catch {
                throw ProviderStreamError<Decoder.Failure>.framing(error)
            }
            for frame in frames {
                do { try decoder.decode(frame, into: &events) } catch { throw ProviderStreamError.stream(error) }
            }
            frames.removeAll(keepingCapacity: true)
            for event in events { yield(event) }
            events.removeAll(keepingCapacity: true)
        }
        guard framer.finish() == .complete else { throw ProviderStreamError<Decoder.Failure>.truncated }
        do { try decoder.finish(into: &events) } catch { throw ProviderStreamError.stream(error) }
        for event in events { yield(event) }
    }
}
