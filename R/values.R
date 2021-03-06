#' Checking values of objects created or displayed by the code
#'
#' \code{check_value} applies a test to the value produced by a line of code. The tests
#' themselves are "match functions" such as \code{match_number}, \code{match_vector}, \code{match_names},
#' \code{match_formula}, \code{match_data.frame} that do the comparison.
#'
#'
#' @details These functions capture the object itself. If there is no such object, a character
#' string with the message is returned. That message will have a 'no_match' attribute
#' If the test passes, the value is returned in the "value" attribute of the capture object
#'
#'

#' @return a function that will take a capture object as input and return
#' a capture object as output. The value of the line (identified by previous locator tests)
#' will be compared to the reference value given when constructing the test.
#' @param test a function taking one value as an argument. The test to
#' run to evaluate the captured value. Test functions should
#' return \code{""} if passing, non-empty message string if not.
#' @param message the message to give if the test fails
#' @param mistake if \code{TRUE}, the specified test is one that should NOT be seen in
#' the code.
#' @seealso \code{\link{check_argument}}
#'
#' @rdname values
#' @export
check_value <- function(test, message = NULL, mistake = FALSE) {
  test_text <- deparse(substitute(test))
  if ("." == test_text) stop("you need to add function evaluation parentheses so that it looks like check_value(stuff)()")
  if (is.null(message))
    message <- ifelse(mistake,
      sprintf("test '%s' shouldn't pass", test_text),
      sprintf("test '%s' failed", test_text))
  f <- function(capture) {
    if ( ! capture$pass) return(capture) # non-passing input given, so don't do test

    if (is.na(capture$line) || (! capture$line %in% capture$valid_lines)) {
      stop("Using check_value() without a valid capture$line. Give a previous test to identify the line who's value is sought.")
    }
    value <- capture$returns[[capture$line]]
    result <- test(value)
    if ((mistake && result == "") || result != "") {
      # either the mistaken pattern was found, so the test should fail
      # or, if <mistake> is TRUE,
      # the pattern was not found when it should have been and
      # so the test fails
      capture$passed = FALSE
      capture$message = message
      # took out the "See line ..." message on 2/3/17
        # paste(message,
        #       sprintf("See line '%s'.",
        #               kill_pipe_tmp_vars(capture$statements[capture$line])))
    }

    capture
  }
  f
}

# remove the internal markers for pipes so that lines print nicely.

kill_pipe_tmp_vars <- function(str) {
  tmp <- gsub("\\.\\.tmp[0-9]*\\.\\. *<- *", "", str)
  gsub("\\.\\.tmp[0-9]\\.\\., *", "", tmp)
}

# Do I want to use this in find_assignment()?
# but doesn't need to be exported
get_match_ind <- function(what, nms, strict = TRUE) {
  if (strict) {
    return(which(nms == what))
  } else {
    # change everything to lower case
    # remove dots and underscores from names
    what <- tolower(gsub("[\\.|_]*", "", what))
    nms <- tolower(gsub("[\\.|_]*", "", nms))
    return(get_match_ind(what, nms, strict = TRUE))
  }
}


# Like check_argument(), but just grabs the value of the argument.
grab_argument <- function(arg_spec) {
  expanded <- as.list(parse(text = arg_spec)[[1]])
  message <- sprintf("couldn't find match to %s", arg_spec)
  the_fun <- expanded[[1]]
  R <- new_test_result()
  f <- function(capture) {
    if ( ! capture$passed) {
      R$passed <- FALSE
      R$message <- message
      R$has_value <- FALSE
      return(R)
    } # short circuit the test
    if ( ! capture$line %in% capture$valid_lines)
      stop("Test designer should specify a previous test that finds the line to examine.")
    all_calls <- get_functions_in_line(capture$expressions, line = capture$line)
    inds = which(all_calls$fun_names == the_fun)
    for (j in inds) {
      call_to_check <- as.call(parse(text = as.character(all_calls$args[[j]])))
      result <- corresponding_arguments(call_to_check, expanded)
      if (length(result$grabbed) ) {
        R$value <- eval(result$grabbed[[1]], envir = capture$names[[capture$line]])
        R$has_value <- TRUE
        return(R)
      }
    }

    R
  }
  f
}





get_function_from_call <- function(call) {
  res <- call[[1]]
  if (is.name(res)) res <- get(as.character(res))

  res
}



# create a correpondance between the arguments in two function calls
corresponding_arguments <- function(one, reference) {
  get_arg_list <- function(the_call) {
    # expand the call so that all arguments have their
    # corresponding names in the formal (or a number for primitives)
    if (is.expression(the_call)) the_call <- as.call(the_call[[1]])
    the_fun <- get_function_from_call(the_call)
    if (is.primitive(the_fun)) {
      result <- as.list(the_call)[-1]
      if(length(result) > 0) names(result) <- 1:length(result)
    } else {
      if (is.list(the_call)) the_call <- as.call(the_call)
      expanded <- match.call(the_fun, the_call)
      result <- as.list(expanded)[-1]
    }

    result
  }
  args_one <- get_arg_list(one)
  args_ref <- get_arg_list(reference)

  grabbed <- list()
  mismatch <- character(0)
  missing <- character(0)

  for (nm in names(args_ref)) {
    if ( ! nm %in% names(args_one)) {
      # keep track of which arguments didn't match
      missing[length(missing) + 1] <- nm
      next
    }
    if (is.call(args_ref[[nm]]) && args_ref[[nm]][[1]] == as.name("eval"))
      args_ref[[nm]] <- eval(args_ref[[nm]])
    if (all(args_ref[[nm]] == as.name("whatever"))) next # we're not concerned about the value
    if (all(args_ref[[nm]] == as.name("grab_this"))) {
      grabbed[[nm]] <- args_one[[nm]]
    } else {
      # check to see if the values match
      if (is.call(args_ref[[nm]]) && is.call(args_one[[nm]])) {
        # function call, so recurse
        result <- corresponding_arguments(args_one[[nm]], args_ref[[nm]])
        grabbed <- c(grabbed, result$grabbed)
        missing <- c(missing, result$missing)
        mismatch <- c(mismatch, result$mismatch)
      } else if (is.name(args_ref[[nm]]) && is.name(args_one[[nm]])){
        if (! identical(args_ref[[nm]], args_one[[nm]]))
          mismatch[length(mismatch) + 1] <- nm
      } else {
        if (is.call(args_ref[[nm]])) args_ref[[nm]] <- eval(args_ref[[nm]])
        if (is.call(args_one[[nm]])) args_one[[nm]] <- eval(args_one[[nm]])
        if (! isTRUE(all.equal(args_ref[[nm]], args_one[[nm]])))
          mismatch[length(mismatch) + 1] <- nm
      }
    }
  }
  return(list(grabbed = grabbed, missing = missing, mismatch = mismatch))
}

# flags for argument grabbing
#' @rdname values
#' @export
grab_this <- as.name("grab_this")
#' @rdname values
#' @export
whatever <- as.name("whatever")
