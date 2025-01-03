extension Optional<Task<Void, Never>> {
    mutating func enqueueAndReplacing(
        _ operation: sending @escaping @isolated(any) () async -> Void
    ) -> Task<Void, Never> {
        let oldTask = self
        let newTask = Task {
            await oldTask?.value
            await operation()
        }
        self = newTask
        return newTask
    }
}
