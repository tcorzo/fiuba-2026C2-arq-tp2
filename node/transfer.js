// internal - call transfer service to execute transfer between accounts
//
// The external transfer service, as received: it always succeeds, after a
// delay randomised between 200 and 400 ms. The assignment fixes it this way.
export async function transfer(fromAccountId, toAccountId, amount) {
  const min = 200;
  const max = 400;
  return new Promise((resolve) =>
    setTimeout(() => resolve(true), Math.random() * (max - min + 1) + min)
  );
}
