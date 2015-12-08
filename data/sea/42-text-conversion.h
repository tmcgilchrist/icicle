#include "41-grisu2.h"

/*
utils
*/

static bool INLINE text_is_digit (char c)
{
    return c >= '0' && c <= '9';
}


/*
iint_t read/write
*/

static const size_t text_iint_max_size = 20; /* 64-bit integer = 19 digits + sign */

static ierror_msg_t INLINE text_read_iint (char **pp, char *pe, iint_t *output_ptr)
{
    char  *p           = *pp;
    size_t buffer_size = pe - p;

    /* handle negative */
    int sign      = 1;
    int sign_size = 0;
    if (buffer_size > 0 && p[0] == '-') {
        sign      = -1;
        sign_size = 1;
        p++;
        buffer_size--;
    }

    /* validate digits */
    size_t digits = 0;
    while (digits < buffer_size) {
        if (!text_is_digit (p[digits]))
            break;
        digits++;
    }

    if (digits == 0)
        return ierror_msg_alloc ("not an integer", *pp, pe - *pp);

    iint_t value = 0;

    /* handle up to 19 digits, assume we're 64-bit */
    switch (digits) {
        case 19:  value += (p[digits-19] - '0') * 1000000000000000000LL;
        case 18:  value += (p[digits-18] - '0') * 100000000000000000LL;
        case 17:  value += (p[digits-17] - '0') * 10000000000000000LL;
        case 16:  value += (p[digits-16] - '0') * 1000000000000000LL;
        case 15:  value += (p[digits-15] - '0') * 100000000000000LL;
        case 14:  value += (p[digits-14] - '0') * 10000000000000LL;
        case 13:  value += (p[digits-13] - '0') * 1000000000000LL;
        case 12:  value += (p[digits-12] - '0') * 100000000000LL;
        case 11:  value += (p[digits-11] - '0') * 10000000000LL;
        case 10:  value += (p[digits-10] - '0') * 1000000000LL;
        case  9:  value += (p[digits- 9] - '0') * 100000000LL;
        case  8:  value += (p[digits- 8] - '0') * 10000000LL;
        case  7:  value += (p[digits- 7] - '0') * 1000000LL;
        case  6:  value += (p[digits- 6] - '0') * 100000LL;
        case  5:  value += (p[digits- 5] - '0') * 10000LL;
        case  4:  value += (p[digits- 4] - '0') * 1000LL;
        case  3:  value += (p[digits- 3] - '0') * 100LL;
        case  2:  value += (p[digits- 2] - '0') * 10LL;
        case  1:  value += (p[digits- 1] - '0');
                  value *= sign;
                  *output_ptr = value;
                  *pp += digits + sign_size;
                  return 0;

        default:  return ierror_msg_alloc ("integer too big", *pp, digits + sign_size);
    }
}

static ierror_msg_t INLINE json_read_iint (char **pp, char *pe, iint_t *output_ptr)
{
    return text_read_iint (pp, pe, output_ptr);
}

static size_t INLINE text_write_iint (iint_t value, char *p)
{
    return snprintf (p, text_iint_max_size, "%lld", value);
}


/*
idouble_t read/write
*/

static const size_t text_idouble_max_size = 32;

static ierror_msg_t INLINE text_read_idouble (char **pp, char *pe, idouble_t *output_ptr)
{
    *output_ptr = strtod (*pp, pp);
    return 0;
}

static ierror_msg_t INLINE json_read_idouble (char **pp, char *pe, idouble_t *output_ptr)
{
    return text_read_idouble (pp, pe, output_ptr);
}

static size_t INLINE text_write_idouble (idouble_t value, char *p)
{
    return grisu2_double_to_string (value, p);
}


/*
ibool_t read
*/

static ierror_msg_t INLINE mask_read_ibool (uint64_t mask, char **pp, char *pe, ibool_t *output_ptr)
{
    static const uint64_t true_mask  = 0x00000000ffffffff;
    static const uint64_t true_bits  = 0x0000000065757274; /* "true" */
    static const uint64_t false_mask = 0x000000ffffffffff;
    static const uint64_t false_bits = 0x00000065736c6166; /* "false" */

    char *p = *pp;

    uint64_t next8 = *(uint64_t *)p | mask;

    int is_true  = (next8 & true_mask)  == true_bits;
    int is_false = (next8 & false_mask) == false_bits;

    if (is_true) {
        *output_ptr = itrue;
        *pp         = p + sizeof ("true") - 1;
    } else if (is_false) {
        *output_ptr = ifalse;
        *pp         = p + sizeof ("false") - 1;
    } else {
        return ierror_msg_alloc ("was not a boolean", p, pe - p);
    }

    return 0;
}

static ierror_msg_t INLINE text_read_ibool (char **pp, char *pe, ibool_t *output_ptr)
{
    static const uint64_t to_lower = 0x2020202020202020;
    return mask_read_ibool (to_lower, pp, pe, output_ptr);
}

static ierror_msg_t INLINE json_read_ibool (char **pp, char *pe, ibool_t *output_ptr)
{
    return mask_read_ibool (0x0, pp, pe, output_ptr);
}


/*
json null read
*/

static ierror_msg_t INLINE json_try_read_null (char **pp, char *pe, ibool_t *was_null_ptr)
{
    static const uint32_t null_bits = 0x000000006c6c756e; /* "null" */

    char *p = *pp;

    uint32_t next4 = *(uint32_t *)p;

    if (next4 != null_bits) {
        *was_null_ptr = ifalse;
        return 0;
    }

    *was_null_ptr = itrue;
    *pp           = p + sizeof ("null") - 1;

    return 0;
}


/*
string read/write
*/

static ierror_msg_t INLINE text_read_istring (imempool_t *pool, char **pp, char *pe, istring_t *output_ptr)
{
    char *p = *pp;

    size_t output_size = pe - p + 1;
    char  *output      = imempool_alloc (pool, output_size);

    output[output_size] = 0;
    memcpy (output, p, output_size - 1);

    *output_ptr = output;
    *pp         = p + output_size - 1;

    return 0;
}

static ierror_msg_t INLINE json_read_istring (imempool_t *pool, char **pp, char *pe, istring_t *output_ptr)
{
    char *p = *pp;

    if (*p++ != '"')
        return ierror_msg_alloc ("missing '\"'",  p, pe - p);

    char *quote_ptr = memchr (p, '"', pe - p);

    if (!quote_ptr)
        return ierror_msg_alloc ("missing closing quote '\"'",  p, pe - p);

    size_t output_size = quote_ptr - p + 1;
    char  *output      = imempool_alloc (pool, output_size);

    output[output_size] = 0;
    memcpy (output, p, output_size - 1);

    *output_ptr = output;
    *pp         = quote_ptr + 1;

    return 0;
}


/*
time read/write
*/

const size_t text_itime_max_size = sizeof ("yyyy-mm-ddThh:mm:ssZ") - 1;

static ierror_msg_t INLINE fixed_read_itime (const char *p, const size_t size, itime_t *output_ptr)
{
    const size_t size0 = size + 1;

                               /* p + 0123456789 */
    const size_t date_only = sizeof ("yyyy-mm-dd");

    if (date_only == size0 &&
        text_is_digit (p[0]) &&
        text_is_digit (p[1]) &&
        text_is_digit (p[2]) &&
        text_is_digit (p[3]) &&
                '-' == p[4]  &&
        text_is_digit (p[5]) &&
        text_is_digit (p[6]) &&
                '-' == p[7]  &&
        text_is_digit (p[8]) &&
        text_is_digit (p[9])) {

        const iint_t year  = p[0] * 1000
                           + p[1] * 100
                           + p[2] * 10
                           + p[3];

        const iint_t month = p[5] * 10
                           + p[6];

        const iint_t day   = p[8] * 10
                           + p[9];

        *output_ptr = itime_from_gregorian (year, month, day, 0, 0, 0);
        return 0;
    }

                               /* p + 01234567890123456789 */
    const size_t date_time = sizeof ("yyyy-mm-ddThh:mm:ssZ");

    if (date_time == size0 &&
        text_is_digit (p[ 0]) &&
        text_is_digit (p[ 1]) &&
        text_is_digit (p[ 2]) &&
        text_is_digit (p[ 3]) &&
                '-' == p[ 4]  &&
        text_is_digit (p[ 5]) &&
        text_is_digit (p[ 6]) &&
                '-' == p[ 7]  &&
        text_is_digit (p[ 8]) &&
        text_is_digit (p[ 9]) &&
                'T' == p[10]  &&
        text_is_digit (p[11]) &&
        text_is_digit (p[12]) &&
                ':' == p[13]  &&
        text_is_digit (p[14]) &&
        text_is_digit (p[15]) &&
                ':' == p[16]  &&
        text_is_digit (p[17]) &&
        text_is_digit (p[18]) &&
                'Z' == p[19] ) {

        const iint_t year   = p[0] * 1000
                            + p[1] * 100
                            + p[2] * 10
                            + p[3];

        const iint_t month  = p[5] * 10
                            + p[6];

        const iint_t day    = p[8] * 10
                            + p[9];

        const iint_t hour   = p[11] * 10
                            + p[12];

        const iint_t minute = p[14] * 10
                            + p[15];

        const iint_t second = p[17] * 10
                            + p[18];

        *output_ptr = itime_from_gregorian (year, month, day, hour, minute, second);
        return 0;
    }

    return ierror_msg_alloc ("expected 'yyyy-mm-dd' or 'yyyy-mm-ddThh:mm:ssZ' but was", p, size);
}

static ierror_msg_t INLINE text_read_itime (char **pp, char *pe, itime_t *output_ptr)
{
    char  *p    = *pp;
    size_t size = pe - p;

    ierror_msg_t error = fixed_read_itime (p, size, output_ptr);
    if (error) return error;

    *pp = pe;

    return 0;
}

static ierror_msg_t INLINE json_read_itime (char **pp, char *pe, itime_t *output_ptr)
{
    char *p = *pp;

    if (*p++ != '"')
        return ierror_msg_alloc ("missing opening quote '\"'",  p, pe - p);

    char *quote_ptr = memchr (p, '"', pe - p);

    if (!quote_ptr)
        return ierror_msg_alloc ("missing closing quote '\"'",  p, pe - p);

    size_t size = quote_ptr - p;

    ierror_msg_t error = fixed_read_itime (p, size, output_ptr);
    if (error) return error;

    *pp = quote_ptr + 1;

    return 0;
}

static size_t INLINE text_write_itime (itime_t value, char *p)
{
    iint_t year, month, day, hour, minute, second;
    itime_to_gregorian (value, &year, &month, &day, &hour, &minute, &second);

    snprintf ( p, text_itime_max_size
             , "%lld-%02lld-%02lldT%02lld:%02lld:%02lldZ"
             , year, month, day, hour, minute, second );

    return text_itime_max_size;
}