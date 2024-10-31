/*unsigned __umulsi3(unsigned a, unsigned b)
{
	unsigned result = 0;

	while (b) {
		if (b & 1)
			result += a;
		a <<= 1;
		b >>= 1;
	}

	return result;
}

int __mulsi3(int a, int b)
{
	unsigned sign = 0;

	if (a < 0) {
		sign ^= 1;
		a = -a;
	}

	if (b < 0) {
		sign ^= 1;
		b = -b;
	}

	unsigned result = __umulsi3(a, b);

	return sign ? -result : result;
}

unsigned __udivmod(unsigned a, unsigned b, int var)
{
	if (b == 0)
		return 0;

	unsigned msb = 1;
	while(b < a && !(b & (1<<31))) {
		msb <<= 1;
		b <<= 1;
	};

	unsigned result = 0;
	while (a && msb) {
		if (b <= a) {
			a -= b;
			result |= msb;
		}
		msb >>= 1;
		b >>= 1;
	}

	return var ? result : a;
}

int __divmod(int a, int b, int var)
{
	unsigned sign = 0, asign = a & (1<<31);

	if (b == 0)
		return 0;

	if (a < 0) {
		sign ^= 1;
		a = -a;
	}

	if (b < 0) {
		sign ^= 1;
		b = -b;
	}

	unsigned result = __udivmod(a, b, var);

	if (var)
		return sign ? -result : result;
	else
		return asign ? -result : result;
}

int __udivsi3(int a, int b)
{
	return __udivmod(a, b, 1);
}

int __umodsi3(int a, int b)
{
	return __udivmod(a, b, 0);
}

int __divsi3(int a, int b)
{
	return __divmod(a, b, 1);
}

int __modsi3(int a, int b)
{
	return __divmod(a, b, 0);
}
*/